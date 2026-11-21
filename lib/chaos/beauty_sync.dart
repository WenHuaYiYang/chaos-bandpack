import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../icon/device_target.dart';
import '../pack/beauty_pack.dart';
import '../protocol/cc_client.dart';
import '../protocol/ops.dart';
import 'delivery.dart';
import 'session.dart';

/// Desktop and mobile share one resource installer. The band only receives
/// validated resource leaves, not the CHP container or a host-chosen path.
abstract final class BeautySync {
  // HELLO has capability bits but no model code. Only the current, documented
  // 10 Pro profile is supported here, and the Bluetooth name must agree.
  static final _tenProName = RegExp(
    r'^(?:Xiaomi Smart Band|Mi Band|小米(?:智能)?手环)\s*10\s*Pro(?:[\s_-][0-9a-f]{4})?$',
    caseSensitive: false,
  );

  static String? unavailableReason(ChaosSession session, DeviceTarget target) {
    if (target != DeviceTarget.tenPro) {
      return '9 Pro 可以保存美化包，但暂不支持直传。可在制作页导出旧版投递表盘。';
    }
    if (!session.isReady || session.releasing || session.delivery == null) {
      return '请先在设备页连接手环。';
    }
    final device = session.connected;
    if (device == null || !_tenProName.hasMatch(device.name.trim())) {
      return '当前连接未识别为小米手环 10 Pro，不能发送这份美化包。';
    }
    if (session.hello?.hasDelivery != true || session.hello?.androidCarrier != true) {
      return '手环上的 ChaosConnect 不支持资源安装，可使用旧版投递表盘。';
    }
    return null;
  }

  static Future<DeliveryTicket> send(
    ChaosSession session,
    BeautyPack pack, {
    void Function(int sent, int total)? onProgress,
    void Function(DeliveryTicket)? onState,
  }) async {
    final reason = unavailableReason(session, pack.device);
    if (reason != null) throw BeautyPackError(reason);
    final delivery = session.delivery!;
    final access = await session.engine!.access();
    if (!session.isReady || session.releasing || !identical(session.delivery, delivery)) {
      throw BeautyPackError('连接已切换，请确认手环后再同步。');
    }
    if (access.authState == 1) throw BeautyPackError('请先在手环上允许本次连接，再点「同步到手环」。');
    if (!access.granted) throw BeautyPackError('手环尚未授权本次连接，请检查手环上的连接权限。');
    final result = await delivery.upload(
      kind: pack.kind == BeautyKind.font ? DeliveryKind.font : DeliveryKind.icon,
      name: pack.name,
      files: pack.files,
      onProgress: onProgress,
      onState: onState,
    );
    if (result.state != DeliveryState.done) {
      throw BeautyPackError('手环没有确认安装完成：${DeliveryState.name(result.state)}。');
    }
    return result;
  }

  static String readableError(Object error) {
    if (error is BeautyPackError) return error.message;
    if (error is CcException) {
      if (error.detail.isNotEmpty) return error.detail;
      return switch (error.status) {
        CcStatus.access => '手环未允许安装，请检查手环上的「安装资源包」权限。',
        CcStatus.exist => '手环已有同名资源，请换个包名或先在手环删除旧包。',
        CcStatus.noSpace => '手环没有可用的安装槽位。',
        CcStatus.busy => '手环正在处理另一次安装或授权，请稍后再试。',
        CcStatus.crc => '手环校验资源失败，没有确认安装。',
        CcStatus.unsupported => '此手环不支持资源直传。',
        _ => '手环没有完成安装（${error.statusName}）。',
      };
    }
    return error.toString().replaceFirst('Bad state: ', '');
  }

  static Future<String?> save(BeautyPack pack) async {
    final bytes = await compute(_encode, pack);
    final fileName = 'Chaos-${pack.device.id}-${pack.kind.name}-${_safeFileStem(pack.name)}.${BeautyPack.extension}';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存美化包',
      fileName: fileName,
      type: Platform.isAndroid ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isAndroid ? null : const [BeautyPack.extension],
      bytes: bytes,
    );
    if (path != null && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return path;
  }

  static Future<({BeautyPack pack, String name})?> pick() async {
    final selected = await FilePicker.platform.pickFiles(
      dialogTitle: '打开美化包',
      // Android's MIME mapper does not recognize .chp. Let its picker show
      // all files; CHP magic, bounds and digests are checked by the decoder.
      type: Platform.isAndroid ? FileType.any : FileType.custom,
      allowedExtensions: Platform.isAndroid ? null : const [BeautyPack.extension],
      withReadStream: true,
    );
    if (selected == null || selected.files.isEmpty) return null;
    final file = selected.files.single;
    if (file.size > BeautyPack.maxBytes) throw BeautyPackError('美化包太大，无法打开。');
    final stream = file.readStream ?? (file.path == null ? null : File(file.path!).openRead());
    final bytes = await readBounded(stream ?? (throw BeautyPackError('读不到美化包内容。')));
    return (pack: await compute(BeautyPack.decode, bytes), name: file.name);
  }

  @visibleForTesting
  static Future<Uint8List> readBounded(Stream<List<int>> stream) async {
    final data = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (chunk.length > BeautyPack.maxBytes - data.length) {
        throw BeautyPackError('美化包太大，无法打开。');
      }
      data.add(chunk);
    }
    return data.takeBytes();
  }

  static Uint8List _encode(BeautyPack pack) => pack.encode();

  static String _safeFileStem(String name) {
    final safe = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_').trim();
    return safe.replaceFirst(RegExp(r'[ .]+$'), '');
  }
}

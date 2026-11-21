import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../pack/shell_writer.dart' show PackError;
import 'chaos_project.dart';
import 'pack_import.dart';

/// 工程级 IO: 打开一份工程(或投递包)、把当前工程存盘。
///
/// 打开时要认两种东西: 自己存的 .chaosproj(zip), 和设备上在用的投递包(.bin
/// 容器)。判据只看头 4 字节 —— 0x50 0x4b 是 zip, 其余交给 PackImport 试容器,
/// 不需要用户先选类型。
abstract final class ProjectActions {
  /// 读一个文件并解析成工程。[bytes] 已由调用方按 32 MB 上限截断。
  ///
  /// 返回工程与"这原本是不是工程文件"的标记: 从投递包导入时, 界面要提示用户
  /// "这是从设备资产反推的", 而不是以为自己打开了一个工程。
  static (ChaosProject, bool) read(Uint8List bytes, {String? name}) {
    if (bytes.length > ProjectCodec.maxBytes) {
      throw ProjectError('文件超过 32 MB');
    }
    if (bytes.length < 4) throw ProjectError('文件太小, 不是工程也不是投递包');
    final bool isZip = bytes[0] == 0x50 && bytes[1] == 0x4b;
    if (isZip) return (ProjectCodec.read(bytes), true);
    try {
      return (PackImport.read(bytes), false);
    } on PackError catch (e) {
      // 容器解析的报错文案本来就是给人看的, 统一包成 ProjectError 让界面只需认一种。
      throw ProjectError(e.message);
    }
  }

  /// 让用户挑一个文件并读回来。取消或读取失败返回 null。
  static Future<(ChaosProject, bool, String)?> pick() async {
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      dialogTitle: '打开工程或投递包',
      type: FileType.any,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;
    final PlatformFile file = picked.files.first;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) throw ProjectError('读不到文件内容');
    final (ChaosProject project, bool isProject) = read(bytes, name: file.name);
    return (project, isProject, file.name);
  }

  /// 把工程存成 .chaosproj。返回落盘路径, 取消时返回 null。
  static Future<String?> save(ChaosProject project, {String name = 'Chaos工程'}) async {
    final Uint8List bytes = ProjectCodec.write(project);
    final String fileName = name + '.' + ProjectCodec.extension;
    final String? path = await FilePicker.platform.saveFile(
      dialogTitle: '保存工程',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const <String>[ProjectCodec.extension],
      bytes: bytes,
    );
    // 桌面端的 saveFile 只回路径不落盘(Android 直接用 bytes 写), 所以要自己补写。
    if (path != null && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return path;
  }

  /// 把任意字节存到用户挑的位置。导出的 .bin 都走这里。
  static Future<String?> saveBytes(
    Uint8List bytes, {
    required String fileName,
    String dialogTitle = '保存',
  }) async {
    final String? path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const <String>['bin'],
      bytes: bytes,
    );
    if (path != null && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    return path;
  }
}

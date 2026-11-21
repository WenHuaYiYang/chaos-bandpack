/// 操作码 / 状态码 / 权限位。逐项对应 `supervisor/bridge/chaos_files.c` 的开头那几张表。
library;

abstract final class CcOp {
  static const int hello = 0x01;
  static const int list = 0x02;
  static const int stat = 0x03;
  static const int mkdir = 0x04;
  static const int remove = 0x05;
  static const int rmdir = 0x06;
  static const int rename = 0x07;
  static const int copy = 0x08;
  static const int openRead = 0x10;
  static const int read = 0x11;
  static const int closeRead = 0x12;
  static const int openWrite = 0x20;
  static const int write = 0x21;
  static const int commit = 0x22;
  static const int abort = 0x23;
  static const int ping = 0x30;
  static const int echo = 0x31; // 链路回显测速: 原样返回 payload
  static const int setDev = 0x40;
  static const int getDev = 0x41;
  static const int getAccess = 0x42;
  static const int disconnect = 0x43;
  static const int nshOpen = 0x50;
  static const int nshWrite = 0x51;
  static const int nshRead = 0x52;
  static const int nshClose = 0x53;
  static const int deliveryBegin = 0x60;
  static const int deliveryStatus = 0x61;
  static const int deliveryOpenFile = 0x62;
  static const int deliveryWrite = 0x63;
  static const int deliveryEndFile = 0x64;
  static const int deliveryCommit = 0x65;
  static const int deliveryAbort = 0x66;
}

abstract final class CcStatus {
  static const int ok = 0;
  static const int bad = 1;
  static const int notFound = 2;
  static const int access = 3;
  static const int exist = 4;
  static const int notDir = 5;
  static const int isDir = 6;
  static const int noSpace = 7;
  static const int busy = 8;
  static const int io = 9;
  static const int crc = 10;
  static const int sequence = 11;
  static const int unsupported = 12;
  static const int tooLarge = 13;
  static const int pending = 14;

  static String name(int s) => switch (s) {
        ok => 'OK',
        bad => 'BAD',
        notFound => 'NOTFOUND',
        access => 'ACCESS',
        exist => 'EXIST',
        notDir => 'NOTDIR',
        isDir => 'ISDIR',
        noSpace => 'NOSPACE',
        busy => 'BUSY',
        io => 'IO',
        crc => 'CRC',
        sequence => 'SEQUENCE',
        unsupported => 'UNSUPPORTED',
        tooLarge => 'TOO_LARGE',
        pending => 'PENDING',
        _ => '未知($s)',
      };
}

/// 权限位。设备侧 `/data/chaos/connect-android.cfg` 里的 mask。
abstract final class CcPerm {
  static const int read = 1; // 默认开
  static const int write = 2; // 默认关
  static const int deleteRename = 4; // 默认关
  static const int devMode = 8; // 默认关
  static const int control = 16; // 预留
  static const int nsh = 32; // 默认关

  static const List<(int, String)> all = [
    (read, '读取文件'),
    (write, '写入文件'),
    (deleteRename, '删除/重命名'),
    (devMode, '开发者模式'),
    (nsh, 'NSH 终端'),
    (control, '设备控制(预留)'),
  ];
}

/// 能力位(HELLO 应答 [3] 与 GET_ACCESS 里出现)
abstract final class CcCap {
  static const int devMode = 1;
  static const int rmdir = 2;
  static const int nsh = 0x10;
  static const int delivery = 0x20;
  static const int android = 0x10;
}

/// 连接策略
abstract final class CcPolicy {
  static const int allow = 0;
  static const int deny = 1;
  static const int ask = 2;
}

#include "spp_channel.h"

#include <flutter/standard_method_codec.h>

#include <chrono>
#include <climits>
#include <system_error>
#include <utility>

namespace {

// 与 ChaosSpp.channel 同一个名字。改一边必须改另一边。
constexpr char kChannelName[] = "com.chaos.chaos_bandpack/spp";
constexpr GUID kChaosConnectService = {0x43434e31, 0x0001, 0x4a10,
                                      {0x80, 0x00, 0x43, 0x48, 0x41, 0x4f, 0x53, 0x01}};
constexpr unsigned long kChaosConnectPort = 19;
constexpr int kDeadline = -1;
constexpr int kCanceled = -2;
using Clock = std::chrono::steady_clock;

// 工作线程独占 socket 和它的网络事件；重试也要先释放上一条 socket。
struct RfcommSocket {
  SOCKET value = INVALID_SOCKET;
  WSAEVENT event = WSA_INVALID_EVENT;
  ~RfcommSocket() { Reset(); }
  void Reset() {
    if (value != INVALID_SOCKET) ::closesocket(value);
    if (event != WSA_INVALID_EVENT) ::WSACloseEvent(event);
    value = INVALID_SOCKET;
    event = WSA_INVALID_EVENT;
  }
};

int OpenRfcomm(RfcommSocket* socket, BTH_ADDR target, GUID service,
               unsigned long port, HANDLE wake, Clock::time_point deadline) {
  socket->value = ::socket(AF_BTH, SOCK_STREAM, BTHPROTO_RFCOMM);
  if (socket->value == INVALID_SOCKET) return ::WSAGetLastError();
  const ULONG authenticate = TRUE;
  if (::setsockopt(socket->value, SOL_RFCOMM, SO_BTH_AUTHENTICATE,
                   reinterpret_cast<const char*>(&authenticate),
                   sizeof(authenticate)) == SOCKET_ERROR) {
    return ::WSAGetLastError();
  }
  socket->event = ::WSACreateEvent();
  if (socket->event == WSA_INVALID_EVENT) return ::WSAGetLastError();
  if (::WSAEventSelect(socket->value, socket->event,
                       FD_CONNECT | FD_READ | FD_WRITE | FD_CLOSE) == SOCKET_ERROR) {
    return ::WSAGetLastError();
  }
  if (::WaitForSingleObject(wake, 0) == WAIT_OBJECT_0) return kCanceled;

  SOCKADDR_BTH address = {};
  address.addressFamily = AF_BTH;
  address.btAddr = target;
  if (port == 0) address.serviceClassId = service;
  address.port = port;
  if (::connect(socket->value, reinterpret_cast<const sockaddr*>(&address),
                static_cast<int>(sizeof(address))) == 0) return 0;
  const int code = ::WSAGetLastError();
  if (code != WSAEWOULDBLOCK) return code;

  const HANDLE events[] = {wake, socket->event};
  while (true) {
    const auto left = std::chrono::ceil<std::chrono::milliseconds>(deadline - Clock::now());
    if (left.count() <= 0) return kDeadline;
    const DWORD event = ::WaitForMultipleObjects(2, events, FALSE,
                                                 static_cast<DWORD>(left.count()));
    if (event == WAIT_OBJECT_0) return kCanceled;
    if (event == WAIT_TIMEOUT) return kDeadline;
    if (event != WAIT_OBJECT_0 + 1) return static_cast<int>(::GetLastError());
    WSANETWORKEVENTS state = {};
    if (::WSAEnumNetworkEvents(socket->value, socket->event, &state) == SOCKET_ERROR) {
      return ::WSAGetLastError();
    }
    if ((state.lNetworkEvents & FD_CONNECT) != 0) return state.iErrorCode[FD_CONNECT_BIT];
    if ((state.lNetworkEvents & FD_CLOSE) != 0) {
      const int error = state.iErrorCode[FD_CLOSE_BIT];
      return error == 0 ? WSAECONNRESET : error;
    }
  }
}

int HexDigit(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

bool ParseAddress(const std::string& text, BTH_ADDR* out) {
  unsigned char octets[6] = {};
  size_t written = 0;
  size_t i = 0;
  while (i < text.size() && written < 6) {
    if (text[i] == ':' || text[i] == '-') {
      ++i;
      continue;
    }
    if (i + 1 >= text.size()) return false;
    const int hi = HexDigit(text[i]);
    const int lo = HexDigit(text[i + 1]);
    if (hi < 0 || lo < 0) return false;
    octets[written] = static_cast<unsigned char>(hi * 16 + lo);
    ++written;
    i += 2;
  }
  if (written != 6 || i < text.size()) return false;
  unsigned long long value = 0;
  for (size_t k = 0; k < 6; ++k) {
    value = (value << 8) | octets[k];
  }
  *out = static_cast<BTH_ADDR>(value);
  return true;
}

// 手环的 UUID 是 8-4-4-4-12 的写法; 中间的分隔符一律跳过, 只认 32 个十六进制位。
bool ParseGuid(const std::string& text, GUID* out) {
  // 8-4-4-4-12 的写法一共 32 个十六进制位 = 16 字节。前三段是整数, 按大端塞进去;
  // 末段 8 字节原样。分隔符一律跳过, 位置由计数决定而不是去数连字符。
  unsigned char bytes[16] = {};
  size_t written = 0;
  size_t i = 0;
  while (i < text.size()) {
    if (text[i] == '-') {
      ++i;
      continue;
    }
    if (i + 1 >= text.size() || written >= 16) return false;
    const int hi = HexDigit(text[i]);
    const int lo = HexDigit(text[i + 1]);
    if (hi < 0 || lo < 0) return false;
    bytes[written] = static_cast<unsigned char>(hi * 16 + lo);
    ++written;
    i += 2;
  }
  if (written != 16) return false;
  out->Data1 = (static_cast<uint32_t>(bytes[0]) << 24) |
               (static_cast<uint32_t>(bytes[1]) << 16) |
               (static_cast<uint32_t>(bytes[2]) << 8) |
               static_cast<uint32_t>(bytes[3]);
  out->Data2 = static_cast<unsigned short>((bytes[4] << 8) | bytes[5]);
  out->Data3 = static_cast<unsigned short>((bytes[6] << 8) | bytes[7]);
  for (size_t k = 0; k < 8; ++k) {
    out->Data4[k] = bytes[8 + k];
  }
  return true;
}

// 连接失败的原因要写成一句人话。把 WSA 码原样抛上去, 界面上就变成
// "PlatformException(connect, 连不上手环 (WSA 10060), null, null)" 这种谁也不想读的东西。
std::string DescribeWsaError(int code) {
  switch (code) {
    case kDeadline:
      return "蓝牙串口未在等待时间内打开";
    case WSAEADDRINUSE:
      return "蓝牙串口正被占用，请先断开手环上的其他 ChaosConnect 连接 (10048)";
    case WSAEACCES:
      return "蓝牙身份验证失败，请检查系统蓝牙里是否已配对 (10013)";
    case WSAEADDRNOTAVAIL:
      return "蓝牙地址或串口通道无效 (10049)";
    case WSAENETUNREACH:
      return "蓝牙链路没能建立 (10051)";
    case WSAENOBUFS:
      return "系统蓝牙资源不足，请稍后再试 (10055)";
    case WSAETIMEDOUT:
      return "手环没有回应蓝牙连接请求 (10060)";
    case WSAECONNREFUSED:
      return "设备拒绝了连接，可能没有开启 ChaosConnect (10061)";
    case WSAEHOSTDOWN:
      // WinSock 蓝牙专用含义：RFCOMM 收到了远端的 DM，和射频超时不同。
      return "设备拒绝打开蓝牙串口，请检查手环的 ChaosConnect 服务和配对状态 (10064)";
    case WSAEHOSTUNREACH:
      return "连不到这台设备";
    default:
      return "连接失败 (WSA " + std::to_string(code) + ")";
  }
}

// 大写的冒号六段地址, SDP 浏览要这个形状的字符串而不是 BTH_ADDR。
std::string FormatAddress(BTH_ADDR target) {
  char buffer[32] = {};
  std::snprintf(buffer, sizeof(buffer), "%02X:%02X:%02X:%02X:%02X:%02X",
                static_cast<unsigned>((target >> 40) & 0xFF),
                static_cast<unsigned>((target >> 32) & 0xFF),
                static_cast<unsigned>((target >> 24) & 0xFF),
                static_cast<unsigned>((target >> 16) & 0xFF),
                static_cast<unsigned>((target >> 8) & 0xFF),
                static_cast<unsigned>(target & 0xFF));
  return std::string(buffer);
}

std::string ToUtf8(const wchar_t* text) {
  if (text == nullptr || text[0] == L'\0') return std::string();
  const int need = ::WideCharToMultiByte(CP_UTF8, 0, text, -1, nullptr, 0, nullptr, nullptr);
  if (need <= 1) return std::string();
  // cbMultiByte 要连结尾的 NUL 一起给, 所以先按 need 分配再截掉最后一位。
  std::string out(static_cast<size_t>(need), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, text, -1, out.data(), need, nullptr, nullptr);
  out.resize(static_cast<size_t>(need - 1));
  return out;
}

// 当前 ACL 连上了或系统记过地址，都不代表已配对。列表和配对结果共用这个判据。
std::vector<BLUETOOTH_DEVICE_INFO> AuthenticatedDevices() {
  std::vector<BLUETOOTH_DEVICE_INFO> devices;
  BLUETOOTH_DEVICE_SEARCH_PARAMS params = {};
  params.dwSize = sizeof(params);
  params.fReturnAuthenticated = TRUE;

  BLUETOOTH_DEVICE_INFO info = {};
  info.dwSize = sizeof(info);
  const HBLUETOOTH_DEVICE_FIND find = ::BluetoothFindFirstDevice(&params, &info);
  if (find == nullptr) return devices;
  do {
    if (info.fAuthenticated != FALSE) devices.push_back(info);
  } while (::BluetoothFindNextDevice(find, &info));
  ::BluetoothFindDeviceClose(find);
  return devices;
}

bool IsAuthenticated(BTH_ADDR target) {
  for (const auto& device : AuthenticatedDevices()) {
    if (device.Address.ullLong == target) return true;
  }
  return false;
}

}  // namespace

SppChannel::SppChannel(flutter::BinaryMessenger* messenger, TaskPoster poster)
    : state_(std::make_shared<State>()), poster_(std::move(poster)) {
  // 通道必须建在平台线程上(构造发生在 FlutterWindow::OnCreate 里)。
  state_->channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  state_->channel->SetMethodCallHandler([this](const Call& call,
                                               std::unique_ptr<Result> result) {
    OnCall(call, std::move(result));
  });

  WSADATA data = {};
  winsock_up_ = ::WSAStartup(MAKEWORD(2, 2), &data) == 0;
}

SppChannel::~SppChannel() {
  // 先把通道摘掉, 再等线程收摊: 已经排进平台线程队列的回调会看到 alive=false
  // 而直接返回, 不会去碰正在析构的通道。
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    state_->alive = false;
    state_->channel->SetMethodCallHandler(nullptr);
    state_->channel.reset();
  }
  if (link_) link_->Cancel();
  if (worker_.joinable()) worker_.join();
  if (scanner_.joinable()) scanner_.join();
  if (winsock_up_) ::WSACleanup();
}

void SppChannel::OnCall(const Call& call, std::unique_ptr<Result> result) {
  const std::string& method = call.method_name();
  if (method == "adapter") {
    result->Success(flutter::EncodableValue(AdapterState()));
  } else if (method == "permissions") {
    // Windows 没有 Android 12 那种运行时蓝牙权限: 设备是"已配对"就说明系统层面
    // 已经授权过, 这里回答 true 而不是假装申请。
    result->Success(flutter::EncodableValue(true));
  } else if (method == "bonded") {
    result->Success(flutter::EncodableValue(BondedDevices()));
  } else if (method == "discover") {
    int timeout_ms = 12000;
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    if (arguments != nullptr) {
      const auto it = arguments->find(flutter::EncodableValue("timeoutMs"));
      if (it != arguments->end()) {
        if (const auto* value = std::get_if<int32_t>(&it->second)) {
          timeout_ms = *value;
        } else if (const auto* wide = std::get_if<int64_t>(&it->second)) {
          timeout_ms = static_cast<int>(*wide);
        }
      }
    }
    // 夹一下: inquiry 的单位是 1.28 秒, 太短等于没搜, 太长界面会以为卡死。
    if (timeout_ms < 3000) timeout_ms = 3000;
    if (timeout_ms > 30000) timeout_ms = 30000;
    Discover(timeout_ms, std::move(result));
  } else if (method == "pair") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    std::string address;
    if (arguments != nullptr) {
      const auto it = arguments->find(flutter::EncodableValue("address"));
      if (it != arguments->end()) {
        if (const auto* text = std::get_if<std::string>(&it->second)) address = *text;
      }
    }
    Pair(address, std::move(result));
  } else if (method == "connect") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    std::string address;
    std::string uuid;
    if (arguments != nullptr) {
      const auto address_it = arguments->find(flutter::EncodableValue("address"));
      if (address_it != arguments->end()) {
        if (const auto* text = std::get_if<std::string>(&address_it->second)) {
          address = *text;
        }
      }
      const auto uuid_it = arguments->find(flutter::EncodableValue("uuid"));
      if (uuid_it != arguments->end()) {
        if (const auto* text = std::get_if<std::string>(&uuid_it->second)) {
          uuid = *text;
        }
      }
    }
    Connect(address, uuid, std::move(result));
  } else if (method == "send") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    std::vector<uint8_t> bytes;
    if (arguments != nullptr) {
      const auto it = arguments->find(flutter::EncodableValue("bytes"));
      if (it != arguments->end()) {
        if (const auto* blob = std::get_if<std::vector<uint8_t>>(&it->second)) {
          bytes = *blob;
        }
      }
    }
    Send(bytes, std::move(result));
  } else if (method == "close") {
    Close(std::move(result));
  } else {
    result->NotImplemented();
  }
}

std::string SppChannel::AdapterState() {
  // Windows 的蓝牙开关状态只有 WinRT 才读得到; 这里能可靠回答的是"有没有无线电"。
  // 硬件开关关掉、无线电被移除时枚举为空, 那就是 off; 剩下的一律报 on, 让连接
  // 自己去失败并把真实错误报上来 —— 比界面上一句瞎猜的"蓝牙未开启"强。
  BLUETOOTH_FIND_RADIO_PARAMS params = {};
  params.dwSize = static_cast<DWORD>(sizeof(params));
  HANDLE radio = nullptr;
  const HBLUETOOTH_RADIO_FIND find = ::BluetoothFindFirstRadio(&params, &radio);
  if (find == nullptr) return "off";
  ::BluetoothFindRadioClose(find);
  if (radio != nullptr) ::CloseHandle(radio);
  return "on";
}

std::vector<flutter::EncodableValue> SppChannel::BondedDevices() {
  std::vector<flutter::EncodableValue> out;
  for (const auto& info : AuthenticatedDevices()) {
    const std::string address = FormatAddress(info.Address.ullLong);
    std::string name = ToUtf8(info.szName);
    if (name.empty()) name = address;
    flutter::EncodableMap device;
    device[flutter::EncodableValue("address")] = flutter::EncodableValue(address);
    device[flutter::EncodableValue("name")] = flutter::EncodableValue(name);
    out.push_back(flutter::EncodableValue(device));
  }
  return out;
}

void SppChannel::Discover(int timeout_ms, std::unique_ptr<Result> result) {
  // 上一次搜索还没收摊就直接说不行: inquiry 期间无线电被占着, 硬起第二次
  // 只会两边都拿不到结果。
  if (searching_.exchange(true)) {
    result->Error("busy", "上一次搜索还没结束");
    return;
  }
  // 上一条搜索线程已经跑完(标志为 false 才会走到这), 先把它收掉再起新的。
  if (scanner_.joinable()) scanner_.join();
  std::shared_ptr<Result> shared(result.release());
  {
    scanner_ = std::thread([this, timeout_ms, shared]() {
    std::vector<flutter::EncodableValue> out;

    BLUETOOTH_DEVICE_SEARCH_PARAMS params = {};
    params.dwSize = static_cast<DWORD>(sizeof(params));
    // 已配对的也要列: 界面拿 paired 标记决定是"点它连"还是"先配对"。
    params.fReturnAuthenticated = TRUE;
    params.fReturnRemembered = TRUE;
    params.fReturnConnected = TRUE;
    params.fReturnUnknown = TRUE;
    params.fIssueInquiry = TRUE;
    // cTimeoutMultiplier 的单位是 1.28 秒, 向上取整, 至少 1。
    params.cTimeoutMultiplier =
        static_cast<unsigned char>(timeout_ms / 1280 + (timeout_ms % 1280 ? 1 : 0));

    BLUETOOTH_DEVICE_INFO info = {};
    info.dwSize = static_cast<DWORD>(sizeof(info));
    const HBLUETOOTH_DEVICE_FIND find = ::BluetoothFindFirstDevice(&params, &info);
    if (find == nullptr) {
      const DWORD code = ::GetLastError();
      // ERROR_NO_MORE_ITEMS 就是"信号发出去了, 附近确实没人应答", 那不算失败。
      // 其余情况(适配器没开、被占用)以前会被当成"没搜到"糊过去, 用户只会觉得
      // 蓝牙坏了, 所以这里要说清楚。
      if (code != ERROR_NO_MORE_ITEMS) {
        searching_ = false;
        std::string message;
        switch (code) {
          case ERROR_INVALID_PARAMETER:
            message = "蓝牙没打开, 搜索发不出去";
            break;
          case ERROR_NOT_READY:
            message = "蓝牙适配器还没准备好, 稍等一下再搜";
            break;
          case ERROR_BUSY:
            message = "蓝牙正忙, 上一次搜索还没收摊";
            break;
          default:
            message = "搜索失败 (Win32 " + std::to_string(code) + ")";
            break;
        }
        auto state = state_;
        poster_([state, shared, message]() {
          std::lock_guard<std::mutex> lock(state->mutex);
          if (state->alive) shared->Error("discover", message);
        });
        return;
      }
    }
    if (find != nullptr) {
      do {
        const unsigned long long address = info.Address.ullLong;
        char buffer[32] = {};
        ::sprintf_s(buffer, sizeof(buffer), "%02llX:%02llX:%02llX:%02llX:%02llX:%02llX",
                    (address >> 40) & 0xFF, (address >> 32) & 0xFF,
                    (address >> 24) & 0xFF, (address >> 16) & 0xFF,
                    (address >> 8) & 0xFF, address & 0xFF);
        std::string name = ToUtf8(info.szName);
        if (name.empty()) name = buffer;
        flutter::EncodableMap device;
        device[flutter::EncodableValue("address")] = flutter::EncodableValue(std::string(buffer));
        device[flutter::EncodableValue("name")] = flutter::EncodableValue(name);
        // fAuthenticated 才是"配对过"; fRemembered 只是记过, 不代表能连。
        device[flutter::EncodableValue("paired")] =
            flutter::EncodableValue(info.fAuthenticated != FALSE);
        out.push_back(flutter::EncodableValue(device));
        info.dwSize = static_cast<DWORD>(sizeof(info));
      } while (::BluetoothFindNextDevice(find, &info));
      ::BluetoothFindDeviceClose(find);
    }
    // 一个都没搜到不是错误: 附近真的没人应答。把空表回给界面, 由它说"没有"。
    searching_ = false;
    PostValue(shared, flutter::EncodableValue(out));
    });
  }
}

void SppChannel::Pair(const std::string& address, std::unique_ptr<Result> result) {
  BTH_ADDR target = 0;
  if (!ParseAddress(address, &target)) {
    result->Error("argument", "地址格式不对");
    return;
  }
  BLUETOOTH_DEVICE_INFO info = {};
  info.dwSize = static_cast<DWORD>(sizeof(info));
  info.Address.ullLong = target;

  // 配对是系统弹窗的事, 这一步会一直等到用户在弹窗上点确定(或者超时)。
  // 所以同样不能占平台线程。
  //
  // 这条线程跑完之前用户可能已经把窗口关了, 所以它**一个 this 成员都不碰**:
  // 通道状态与回平台的投递函数在起线程时就拷进闭包, 通道没了( alive=false )
  // 就直接把结果丢掉。用成员线程 join 也行不通 —— 它要卡在系统弹窗上等到
  // 用户点确定, 那会让关窗口一起卡住。
  std::shared_ptr<State> state = state_;
  TaskPoster poster = poster_;
  std::shared_ptr<Result> shared(result.release());
  std::thread([state, poster, info, shared]() mutable {
    // Pair 可晚于窗口退出，投递本身（不只是回调）也必须受引擎生命周期保护。
    const auto post = [&](std::function<void()> task) {
      std::lock_guard<std::mutex> lock(state->mutex);
      if (state->alive) poster(std::move(task));
    };
    const BTH_ADDR target_address = info.Address.ullLong;
    const DWORD rc = ::BluetoothAuthenticateDeviceEx(nullptr, nullptr, &info, nullptr,
                                                     MITMProtectionNotRequiredBonding);
    const bool may_be_paired = rc == ERROR_SUCCESS || rc == ERROR_ALREADY_EXISTS ||
                               rc == ERROR_NO_MORE_ITEMS;
    bool paired = may_be_paired && IsAuthenticated(target_address);
    // 真机上认证 API 曾返回成功，但随后只有临时 ACL，系统没有绑定记录。
    // 给系统短暂的落盘时间，不能仅凭 API 的返回值把手环移到「已配对」。
    for (int i = 0; rc == ERROR_SUCCESS && !paired && i < 12; ++i) {
      std::this_thread::sleep_for(std::chrono::milliseconds(250));
      paired = IsAuthenticated(target_address);
    }
    if (paired) {
      post([state, shared]() {
        std::lock_guard<std::mutex> lock(state->mutex);
        if (!state->alive) return;
        shared->Success(flutter::EncodableValue(true));
      });
      return;
    }
    std::string message;
    switch (rc) {
      case ERROR_CANCELLED:
        message = "配对被取消了";
        break;
      case ERROR_NOT_SUPPORTED:
        message = "这台设备不支持从电脑上发起配对";
        break;
      case WAIT_TIMEOUT:
      case ERROR_TIMEOUT:
        message = "配对超时。请在手环重新点「发起蓝牙配对」，再试一次";
        break;
      case ERROR_SUCCESS:
      case ERROR_ALREADY_EXISTS:
      case ERROR_NO_MORE_ITEMS:
        message = "Windows 没有确认已配对。请在手环重新点「发起蓝牙配对」，再试一次";
        break;
      default:
        message = "配对失败 (Win32 " + std::to_string(rc) + ")";
        break;
    }
    post([state, shared, message]() {
      std::lock_guard<std::mutex> lock(state->mutex);
      if (!state->alive) return;
      shared->Error("pair", message);
    });
  }).detach();
}

void SppChannel::Connect(const std::string& address, const std::string& uuid,
                         std::unique_ptr<Result> result) {
  BTH_ADDR target = 0;
  GUID service = {};
  if (!ParseAddress(address, &target) || !ParseGuid(uuid, &service)) {
    result->Error("argument", "address 或 uuid 格式不对");
    return;
  }
  if (link_ || searching_) {
    result->Error("busy", "蓝牙正在搜索或处理上一条连接，请稍后再连");
    return;
  }
  if (!winsock_up_) {
    result->Error("unsupported", "本机不能走蓝牙串口");
    return;
  }
  const HANDLE wake = ::CreateEventW(nullptr, FALSE, FALSE, nullptr);
  if (wake == nullptr) {
    result->Error("rfcomm", "Windows 无法启动蓝牙连接任务");
    return;
  }
  auto shared = std::shared_ptr<Result>(std::move(result));
  link_ = std::make_shared<Link>(wake);
  try {
    worker_ = std::thread(&SppChannel::ConnectAndRead, this, link_, target, service, shared);
  } catch (const std::system_error&) {
    link_.reset();
    shared->Error("rfcomm", "Windows 无法启动蓝牙连接任务");
  }
}

void SppChannel::Send(const std::vector<uint8_t>& bytes, std::unique_ptr<Result> result) {
  if (!link_ || !link_->open || link_->canceled) {
    result->Error("closed", "载波未连接");
    return;
  }
  if (!bytes.empty()) {
    {
      std::lock_guard<std::mutex> lock(link_->mutex);
      link_->outgoing.push_back(bytes);
    }
    ::SetEvent(link_->wake);
  }
  result->Success();
}

void SppChannel::ConnectAndRead(std::shared_ptr<Link> link, BTH_ADDR target,
                                GUID service, std::shared_ptr<Result> result) {
  RfcommSocket socket;
  const auto start = Clock::now();
  const bool chaos = IsEqualGUID(service, kChaosConnectService);
  const auto deadline = start + std::chrono::seconds(24);
  const auto uuid_deadline = chaos ? start + std::chrono::seconds(7) : deadline;
  int code = OpenRfcomm(&socket, target, service, 0, link->wake, uuid_deadline);
  const auto describe = [](int error) { return DescribeWsaError(error); };
  const bool fallback = code == kDeadline || code == WSAEHOSTDOWN ||
                        code == WSAECONNREFUSED || code == WSAEADDRNOTAVAIL ||
                        code == WSASERVICE_NOT_FOUND || code == WSATYPE_NOT_FOUND;
  std::string connect_error;
  if (code != 0 && code != kCanceled) connect_error = "按服务连接：" + describe(code);
  if (fallback && chaos && !link->canceled && Clock::now() < deadline) {
    socket.Reset();
    code = OpenRfcomm(&socket, target, service, kChaosConnectPort, link->wake, deadline);
    if (code != 0 && code != kCanceled) connect_error += "；专用通道 19：" + describe(code);
  }

  auto state = state_;
  const bool opened = code == 0 && !link->canceled;
  std::string disconnect_reason;
  if (opened) {
    link->open = true;
    poster_([state, link, result]() {
      std::lock_guard<std::mutex> lock(state->mutex);
      if (!state->alive) return;
      if (link->canceled) result->Error("canceled", "已取消连接");
      else result->Success();
    });
    disconnect_reason = RunIo(link, socket.value, socket.event);
    link->open = false;
  }
  socket.Reset();

  poster_([this, state, link, result, opened, connect_error, disconnect_reason]() {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (!state->alive) return;
    if (worker_.joinable()) worker_.join();  // I/O 已结束；仅回收线程句柄。
    link_.reset();
    if (!opened) {
      if (link->canceled) result->Error("canceled", "已取消连接");
      else result->Error("rfcomm", connect_error);
    } else if (!link->canceled) {
      state->channel->InvokeMethod("closed", std::make_unique<flutter::EncodableValue>(
                                                    disconnect_reason));
    }
    for (auto& waiter : close_waiters_) waiter->Success();
    close_waiters_.clear();
  });
}

std::string SppChannel::RunIo(const std::shared_ptr<Link>& link, SOCKET socket,
                              WSAEVENT network_event) {
  const HANDLE events[] = {link->wake, network_event};
  std::vector<uint8_t> input(4096);
  std::vector<uint8_t> output;
  size_t offset = 0;
  bool peer_closed = false;
  std::string close_reason = "手环关闭了蓝牙串口";
  while (!link->canceled) {
    if (offset == output.size()) {
      std::lock_guard<std::mutex> lock(link->mutex);
      output.clear();
      offset = 0;
      if (!link->outgoing.empty()) {
        output = std::move(link->outgoing.front());
        link->outgoing.pop_front();
      }
    }
    bool wrote = false;
    if (!peer_closed && offset < output.size()) {
      const size_t bytes = output.size() - offset;
      const int n = ::send(socket, reinterpret_cast<const char*>(output.data() + offset),
                           bytes > INT_MAX ? INT_MAX : static_cast<int>(bytes), 0);
      if (n > 0) {
        offset += static_cast<size_t>(n);
        wrote = true;
      } else if (n == 0) {
        return "蓝牙串口写入已中断";
      } else {
        const int error = ::WSAGetLastError();
        if (error != WSAEWOULDBLOCK) return "蓝牙串口写入失败：" + DescribeWsaError(error);
      }
    }

    const int n = ::recv(socket, reinterpret_cast<char*>(input.data()),
                         static_cast<int>(input.size()), 0);
    if (n > 0) {
      PostEvent(link, "chunk", flutter::EncodableValue(std::vector<uint8_t>(
                                      input.begin(), input.begin() + n)));
      continue;
    }
    if (n == 0) return close_reason;
    const int error = ::WSAGetLastError();
    if (error == WSAECONNRESET) return "手环断开了蓝牙串口 (10054)";
    if (error != WSAEWOULDBLOCK) return "蓝牙串口读取失败：" + DescribeWsaError(error);
    if (peer_closed) return close_reason;
    if (wrote) continue;

    const DWORD event = ::WaitForMultipleObjects(2, events, FALSE, INFINITE);
    if (event == WAIT_OBJECT_0) continue;
    if (event != WAIT_OBJECT_0 + 1) return "Windows 无法等待蓝牙串口数据";
    WSANETWORKEVENTS state = {};
    if (::WSAEnumNetworkEvents(socket, network_event, &state) == SOCKET_ERROR) {
      return "蓝牙串口事件读取失败：" + DescribeWsaError(::WSAGetLastError());
    }
    if ((state.lNetworkEvents & FD_CLOSE) != 0) {
      peer_closed = true;
      const int close_error = state.iErrorCode[FD_CLOSE_BIT];
      if (close_error != 0) close_reason += " (" + std::to_string(close_error) + ")";
    }
    if ((state.lNetworkEvents & FD_READ) != 0 && state.iErrorCode[FD_READ_BIT] != 0) {
      return "蓝牙串口读取失败：" + DescribeWsaError(state.iErrorCode[FD_READ_BIT]);
    }
    if ((state.lNetworkEvents & FD_WRITE) != 0 && state.iErrorCode[FD_WRITE_BIT] != 0) {
      return "蓝牙串口写入失败：" + DescribeWsaError(state.iErrorCode[FD_WRITE_BIT]);
    }
  }
  return close_reason;
}

void SppChannel::Close(std::unique_ptr<Result> result) {
  if (!link_) {
    result->Success();
    return;
  }
  close_waiters_.push_back(std::move(result));
  link_->Cancel();
}

void SppChannel::PostEvent(const std::shared_ptr<Link>& link, const std::string& method,
                            flutter::EncodableValue argument) {
  auto state = state_;
  poster_([state, link, method, argument = std::move(argument)]() {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (!state->alive || link->canceled) return;
    state->channel->InvokeMethod(
        method, std::make_unique<flutter::EncodableValue>(argument));
  });
}

void SppChannel::PostValue(std::shared_ptr<Result> result,
                           flutter::EncodableValue value) {
  std::shared_ptr<State> state = state_;
  poster_([state, result, value = std::move(value)]() {
    std::lock_guard<std::mutex> lock(state->mutex);
    if (!state->alive) return;
    result->Success(value);
  });
}

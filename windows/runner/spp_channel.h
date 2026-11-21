#ifndef RUNNER_SPP_CHANNEL_H_
#define RUNNER_SPP_CHANNEL_H_

// winsock2.h 必须先于 windows.h, 否则 winsock.h 先被拉进来, 两者结构体重定义。
#include <winsock2.h>
// clang-format off
#include <windows.h>
// clang-format on

#include <ws2bth.h>
#include <bluetoothapis.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// 桌面端的经典蓝牙 SPP 载波, 与 Android 侧 MainActivity.kt 同名同语义:
//
//   通道 com.chaos.chaos_bandpack/spp
//   方法 adapter / permissions / bonded / connect / send / close
//   回调 chunk(字节) / closed(原因)
//
// 手环注册私有 UUID 43434e31-0001-4a10-8000-4348414f5301。Windows 优先由系统
// 通过 UUID 查 SDP；在当前固件上只回退到 ChaosConnect 已知的专用通道 19。
class SppChannel {
 public:
  // 把一段闭包送回平台线程。连接与读循环都在工作线程上, 碰 Flutter 的通道必须回平台线程。
  using TaskPoster = std::function<void(std::function<void()>)>;

  SppChannel(flutter::BinaryMessenger* messenger, TaskPoster poster);
  ~SppChannel();

  SppChannel(const SppChannel&) = delete;
  SppChannel& operator=(const SppChannel&) = delete;

 private:
  using Call = flutter::MethodCall<flutter::EncodableValue>;
  using Result = flutter::MethodResult<flutter::EncodableValue>;

  // 线程上发出去的回调只能通过它碰通道: 窗口销毁时析构函数在平台线程上把 channel
  // 置空, 已经排进队列但还没跑的任务因此不会碰到已释放的对象。
  struct State {
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
    std::mutex mutex;
    bool alive = true;
  };

  void OnCall(const Call& call, std::unique_ptr<Result> result);
  std::string AdapterState();
  std::vector<flutter::EncodableValue> BondedDevices();
  void Connect(const std::string& address, const std::string& uuid,
               std::unique_ptr<Result> result);
  // 主动搜附近的设备。inquiry 是阻塞的(十几秒), 所以甩到工作线程上跑。
  void Discover(int timeout_ms, std::unique_ptr<Result> result);
  void Pair(const std::string& address, std::unique_ptr<Result> result);
  void Send(const std::vector<uint8_t>& bytes, std::unique_ptr<Result> result);
  void Close(std::unique_ptr<Result> result);

  // 只有 worker 访问 Winsock socket。平台线程仅发信号，等资源释放后再回复 close。
  struct Link {
    explicit Link(HANDLE event) : wake(event) {}
    ~Link() { ::CloseHandle(wake); }
    void Cancel() {
      canceled = true;
      ::SetEvent(wake);
    }
    const HANDLE wake;
    std::atomic<bool> canceled{false};
    std::atomic<bool> open{false};
    std::mutex mutex;
    std::deque<std::vector<uint8_t>> outgoing;
  };

  void ConnectAndRead(std::shared_ptr<Link> link, BTH_ADDR target, GUID service,
                      std::shared_ptr<Result> result);
  std::string RunIo(const std::shared_ptr<Link>& link, SOCKET socket,
                    WSAEVENT network_event);
  void PostEvent(const std::shared_ptr<Link>& link, const std::string& method,
                 flutter::EncodableValue argument);
  void PostValue(std::shared_ptr<Result> result, flutter::EncodableValue value);

  std::shared_ptr<State> state_;
  TaskPoster poster_;
  // link_、线程句柄和关闭回执由平台线程维护。
  std::shared_ptr<Link> link_;
  std::vector<std::unique_ptr<Result>> close_waiters_;
  std::thread worker_;
  std::thread scanner_;
  std::atomic<bool> searching_{false};
  bool winsock_up_ = false;
};

#endif  // RUNNER_SPP_CHANNEL_H_

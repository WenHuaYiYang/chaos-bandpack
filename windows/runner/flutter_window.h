#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "spp_channel.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // 经典蓝牙 SPP 载波(通道 com.chaos.chaos_bandpack/spp)。
  // 必须在 flutter_controller_ 之后声明: 成员逆序析构, 通道要先于引擎消失,
  // 否则后台线程回写到已经拆掉的 messenger 上。
  std::unique_ptr<SppChannel> spp_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

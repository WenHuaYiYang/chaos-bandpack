#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);

  // Phone-shaped window, centred on the primary screen. The previous
  // 1280x720 put the bottom navigation bar off-screen on a 1440x960 desktop.
  // NOTE: keep this file pure ASCII (MSVC has no /utf-8 here), so the title
  // uses universal character names instead of literal CJK.
  const int kWidth = 468;
  const int kHeight = 880;
  // The window manager multiplies this origin and size by the monitor scale
  // factor, while GetSystemMetrics reports physical pixels, so divide it out
  // first. Without this the window lands off-screen on a scaled display.
  const double kScale = ::GetDpiForSystem() / 96.0;
  const int screen_w = static_cast<int>(::GetSystemMetrics(SM_CXSCREEN) / kScale);
  const int screen_h = static_cast<int>(::GetSystemMetrics(SM_CYSCREEN) / kScale);
  int x = (screen_w - kWidth) / 2;
  int y = (screen_h - kHeight) / 2;
  if (x < 0) x = 0;
  if (y < 0) y = 0;

  Win32Window::Point origin(x, y);
  Win32Window::Size size(kWidth, kHeight);
  if (!window.Create(L"Chaos \u540c\u6b65\u5668", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

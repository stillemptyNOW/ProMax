#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_call.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>

#include <memory>
#include <string>

#include "win32_window.h"

inline constexpr ULONG_PTR kActivateInstanceMessage = 0x50524D41;

inline constexpr ULONG_PTR kAppLinkMessage = static_cast<ULONG_PTR>(WM_USER + 2);

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  void SetStartHidden(bool start_hidden);

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  using Channel = flutter::MethodChannel<flutter::EncodableValue>;
  using Call = flutter::MethodCall<flutter::EncodableValue>;
  using Result = flutter::MethodResult<flutter::EncodableValue>;

  void RegisterChannels();
  void HandleWindowCall(const Call& call, std::unique_ptr<Result> result);
  void HandleBadgeCall(const Call& call, std::unique_ptr<Result> result);
  void HandleScreenCall(const Call& call, std::unique_ptr<Result> result);

  void Reveal();
  void HideToTray();
  void Flash();
  void RequestQuit();
  void UpdateTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  std::unique_ptr<Channel> window_channel_;
  std::unique_ptr<Channel> badge_channel_;
  std::unique_ptr<Channel> screen_channel_;

  bool start_hidden_ = false;
  bool tray_added_ = false;
  HWND tray_window_ = nullptr;
  UINT taskbar_created_message_ = 0;
  std::wstring tray_tooltip_ = L"ProMax";
  std::wstring tray_open_label_ = L"Open ProMax";
  std::wstring tray_exit_label_ = L"Exit";
};

#endif  // RUNNER_FLUTTER_WINDOW_H_

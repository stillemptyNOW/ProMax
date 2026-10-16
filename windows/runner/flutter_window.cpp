#include "flutter_window.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <wchar.h>

#include <optional>
#include <utility>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "utils.h"

namespace {

constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayCallbackMessage = WM_APP + 1;
constexpr UINT kQuitMessage = WM_APP + 2;
constexpr UINT_PTR kTrayOpenCommand = 1001;
constexpr UINT_PTR kTrayExitCommand = 1002;
constexpr UINT_PTR kQuitTimerId = 0x5051;
constexpr UINT kQuitTimeoutMs = 5000;

constexpr const wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr const wchar_t kRunValue[] = L"ProMax";

const flutter::EncodableValue* FindArgument(
    const flutter::EncodableValue* arguments,
    const char* key) {
  if (arguments == nullptr) {
    return nullptr;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) {
    return nullptr;
  }
  const auto found = map->find(flutter::EncodableValue(key));
  return found == map->end() ? nullptr : &found->second;
}

bool BoolArgument(const flutter::EncodableValue* arguments, const char* key) {
  const auto* value = FindArgument(arguments, key);
  if (value == nullptr) {
    return false;
  }
  const auto* flag = std::get_if<bool>(value);
  return flag != nullptr && *flag;
}

int64_t IntArgument(const flutter::EncodableValue* arguments, const char* key) {
  const auto* value = FindArgument(arguments, key);
  if (value == nullptr) {
    return 0;
  }
  return value->TryGetLongValue().value_or(0);
}

std::wstring StringArgument(const flutter::EncodableValue* arguments,
                            const char* key) {
  const auto* value = FindArgument(arguments, key);
  if (value == nullptr) {
    return std::wstring();
  }
  const auto* text = std::get_if<std::string>(value);
  return text == nullptr ? std::wstring() : Utf16FromUtf8(*text);
}

std::wstring ExecutablePath() {
  std::wstring path(32768, L'\0');
  const DWORD length = GetModuleFileNameW(
      nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (length == 0 || length >= path.size()) {
    return std::wstring();
  }
  path.resize(length);
  return path;
}

bool IsAutostartEnabled() {
  return RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ,
                      nullptr, nullptr, nullptr) == ERROR_SUCCESS;
}

bool SetAutostartEnabled(bool enabled) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kRunKey, 0, nullptr,
                      REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr, &key,
                      nullptr) != ERROR_SUCCESS) {
    return false;
  }
  LSTATUS status = ERROR_SUCCESS;
  if (enabled) {
    const std::wstring executable = ExecutablePath();
    if (executable.empty()) {
      RegCloseKey(key);
      return false;
    }
    const std::wstring command = L"\"" + executable + L"\" --minimized";
    status = RegSetValueExW(
        key, kRunValue, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    status = RegDeleteValueW(key, kRunValue);
    if (status == ERROR_FILE_NOT_FOUND) {
      status = ERROR_SUCCESS;
    }
  }
  RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::SetStartHidden(bool start_hidden) {
  start_hidden_ = start_hidden;
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  RegisterChannels();

  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
  UpdateTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) {
      this->Show();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  window_channel_ = nullptr;
  badge_channel_ = nullptr;
  screen_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::RegisterChannels() {
  flutter::BinaryMessenger* messenger =
      flutter_controller_->engine()->messenger();
  const auto* codec = &flutter::StandardMethodCodec::GetInstance();

  window_channel_ = std::make_unique<Channel>(
      messenger, "io.github.stillemptynow.promax/window", codec);
  window_channel_->SetMethodCallHandler(
      [this](const Call& call, std::unique_ptr<Result> result) {
        HandleWindowCall(call, std::move(result));
      });

  badge_channel_ = std::make_unique<Channel>(
      messenger, "io.github.stillemptynow.promax/launcher_badge", codec);
  badge_channel_->SetMethodCallHandler(
      [this](const Call& call, std::unique_ptr<Result> result) {
        HandleBadgeCall(call, std::move(result));
      });

  screen_channel_ = std::make_unique<Channel>(
      messenger, "io.github.stillemptynow.promax/screen", codec);
  screen_channel_->SetMethodCallHandler(
      [this](const Call& call, std::unique_ptr<Result> result) {
        HandleScreenCall(call, std::move(result));
      });
}

void FlutterWindow::HandleWindowCall(const Call& call,
                                     std::unique_ptr<Result> result) {
  const std::string& method = call.method_name();
  HWND hwnd = GetHandle();
  if (method == "presence") {
    flutter::EncodableMap presence;
    presence[flutter::EncodableValue("visible")] =
        flutter::EncodableValue(hwnd != nullptr && IsWindowVisible(hwnd) != FALSE);
    presence[flutter::EncodableValue("minimized")] =
        flutter::EncodableValue(hwnd != nullptr && IsIconic(hwnd) != FALSE);
    presence[flutter::EncodableValue("focused")] =
        flutter::EncodableValue(hwnd != nullptr && GetForegroundWindow() == hwnd);
    result->Success(flutter::EncodableValue(presence));
  } else if (method == "reveal") {
    Reveal();
    result->Success();
  } else if (method == "hide") {
    HideToTray();
    result->Success();
  } else if (method == "flash") {
    Flash();
    result->Success();
  } else if (method == "quit") {
    result->Success();
    if (hwnd != nullptr) {
      PostMessage(hwnd, kQuitMessage, 0, 0);
    }
  } else if (method == "autostart") {
    result->Success(flutter::EncodableValue(IsAutostartEnabled()));
  } else if (method == "setAutostart") {
    const bool enabled = BoolArgument(call.arguments(), "enabled");
    result->Success(flutter::EncodableValue(SetAutostartEnabled(enabled)));
  } else if (method == "setTrayLabels") {
    const std::wstring open_label = StringArgument(call.arguments(), "open");
    const std::wstring exit_label = StringArgument(call.arguments(), "exit");
    if (!open_label.empty()) {
      tray_open_label_ = open_label;
    }
    if (!exit_label.empty()) {
      tray_exit_label_ = exit_label;
    }
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void FlutterWindow::HandleBadgeCall(const Call& call,
                                    std::unique_ptr<Result> result) {
  const std::string& method = call.method_name();
  if (method == "isSupported") {
    result->Success(flutter::EncodableValue(true));
  } else if (method == "sync") {
    const bool enabled = BoolArgument(call.arguments(), "enabled");
    const int64_t count = IntArgument(call.arguments(), "count");
    tray_tooltip_ = enabled && count > 0
                        ? L"ProMax (" + std::to_wstring(count) + L")"
                        : std::wstring(L"ProMax");
    UpdateTrayIcon();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void FlutterWindow::HandleScreenCall(const Call& call,
                                     std::unique_ptr<Result> result) {
  if (call.method_name() != "setKeepAwake") {
    result->NotImplemented();
    return;
  }
  const bool enabled = BoolArgument(call.arguments(), "enabled");
  SetThreadExecutionState(enabled ? (ES_CONTINUOUS | ES_DISPLAY_REQUIRED |
                                     ES_SYSTEM_REQUIRED)
                                  : ES_CONTINUOUS);
  result->Success();
}

void FlutterWindow::Reveal() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  if (!IsWindowVisible(hwnd)) {
    Show();
  }
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }
  SetForegroundWindow(hwnd);
  if (flutter_controller_) {
    flutter_controller_->ForceRedraw();
  }
}

void FlutterWindow::HideToTray() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  SavePlacement(hwnd);
  ShowWindow(hwnd, SW_HIDE);
}

void FlutterWindow::Flash() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr || GetForegroundWindow() == hwnd ||
      !IsWindowVisible(hwnd)) {
    return;
  }
  FLASHWINFO info{};
  info.cbSize = static_cast<UINT>(sizeof(info));
  info.hwnd = hwnd;
  info.dwFlags = FLASHW_TRAY | FLASHW_TIMERNOFG;
  info.uCount = 0;
  info.dwTimeout = 0;
  FlashWindowEx(&info);
}

void FlutterWindow::RequestQuit() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  SetTimer(hwnd, kQuitTimerId, kQuitTimeoutMs, nullptr);
  if (!window_channel_) {
    PostMessage(hwnd, kQuitMessage, 0, 0);
    return;
  }
  window_channel_->InvokeMethod(
      "quitRequested", nullptr,
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          nullptr,
          [hwnd](const std::string& code, const std::string& message,
                 const flutter::EncodableValue* details) {
            PostMessage(hwnd, kQuitMessage, 0, 0);
          },
          [hwnd]() { PostMessage(hwnd, kQuitMessage, 0, 0); }));
}

void FlutterWindow::UpdateTrayIcon() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  NOTIFYICONDATAW data{};
  data.cbSize = static_cast<DWORD>(sizeof(data));
  data.hWnd = hwnd;
  data.uID = kTrayIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = kTrayCallbackMessage;
  data.hIcon = static_cast<HICON>(LoadImageW(
      GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
      LR_DEFAULTCOLOR | LR_SHARED));
  wcsncpy_s(data.szTip, ARRAYSIZE(data.szTip), tray_tooltip_.c_str(),
            _TRUNCATE);
  if (tray_added_) {
    Shell_NotifyIconW(NIM_MODIFY, &data);
    return;
  }
  tray_added_ = Shell_NotifyIconW(NIM_ADD, &data) != FALSE;
  if (tray_added_) {
    tray_window_ = hwnd;
  }
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_added_) {
    return;
  }
  NOTIFYICONDATAW data{};
  data.cbSize = static_cast<DWORD>(sizeof(data));
  data.hWnd = tray_window_;
  data.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &data);
  tray_added_ = false;
  tray_window_ = nullptr;
}

void FlutterWindow::ShowTrayMenu() {
  HWND hwnd = GetHandle();
  if (hwnd == nullptr) {
    return;
  }
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  AppendMenuW(menu, MF_STRING, kTrayOpenCommand, tray_open_label_.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayExitCommand, tray_exit_label_.c_str());
  SetMenuDefaultItem(menu, static_cast<UINT>(kTrayOpenCommand), FALSE);

  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(hwnd);
  const UINT_PTR command = static_cast<UINT_PTR>(TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_BOTTOMALIGN,
      cursor.x, cursor.y, 0, hwnd, nullptr));
  PostMessage(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);

  if (command == kTrayOpenCommand) {
    Reveal();
  } else if (command == kTrayExitCommand) {
    RequestQuit();
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (taskbar_created_message_ != 0 && message == taskbar_created_message_) {
    tray_added_ = false;
    UpdateTrayIcon();
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;

    case kTrayCallbackMessage:
      switch (static_cast<UINT>(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          Reveal();
          break;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          break;
      }
      return 0;

    case kQuitMessage:
      KillTimer(hwnd, kQuitTimerId);
      DestroyWindow(hwnd);
      return 0;

    case WM_TIMER:
      if (wparam == kQuitTimerId) {
        KillTimer(hwnd, kQuitTimerId);
        DestroyWindow(hwnd);
        return 0;
      }
      break;

    case WM_COPYDATA: {
      const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
      if (data != nullptr && data->dwData == kActivateInstanceMessage) {
        Reveal();
        return TRUE;
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

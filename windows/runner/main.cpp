#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>
#include <wchar.h>

#include <cwctype>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kAppUserModelId[] = L"io.github.stillemptynow.promax";
constexpr char kMinimizedArgument[] = "--minimized";
constexpr int kInstanceLookupAttempts = 50;
constexpr DWORD kInstanceLookupDelayMs = 100;
constexpr UINT kForwardTimeoutMs = 5000;

std::wstring ProcessImagePath(HANDLE process) {
  std::wstring path(32768, L'\0');
  DWORD size = static_cast<DWORD>(path.size());
  if (!QueryFullProcessImageNameW(process, 0, path.data(), &size)) {
    return std::wstring();
  }
  path.resize(size);
  for (wchar_t& character : path) {
    character = static_cast<wchar_t>(std::towlower(character));
  }
  return path;
}

std::wstring InstanceMutexName(const std::wstring& executable) {
  unsigned long long hash = 1469598103934665603ULL;
  for (const wchar_t character : executable) {
    hash ^= static_cast<unsigned long long>(character);
    hash *= 1099511628211ULL;
  }
  return L"Local\\ProMax-" + std::to_wstring(hash);
}

struct InstanceSearch {
  std::wstring executable;
  HWND window = nullptr;
  DWORD process_id = 0;
};

BOOL CALLBACK FindInstanceWindow(HWND hwnd, LPARAM lparam) {
  auto* search = reinterpret_cast<InstanceSearch*>(lparam);
  wchar_t class_name[64] = {};
  if (GetClassNameW(hwnd, class_name,
                    static_cast<int>(ARRAYSIZE(class_name))) == 0 ||
      wcscmp(class_name, kRunnerWindowClassName) != 0) {
    return TRUE;
  }
  DWORD process_id = 0;
  GetWindowThreadProcessId(hwnd, &process_id);
  if (process_id == 0 || process_id == GetCurrentProcessId()) {
    return TRUE;
  }
  HANDLE process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (process == nullptr) {
    return TRUE;
  }
  const std::wstring path = ProcessImagePath(process);
  CloseHandle(process);
  if (path != search->executable) {
    return TRUE;
  }
  search->window = hwnd;
  search->process_id = process_id;
  return FALSE;
}

bool IsLinkArgument(const std::string& argument) {
  const size_t colon = argument.find(':');
  if (colon == std::string::npos || colon < 2) {
    return false;
  }
  for (size_t i = 0; i < colon; ++i) {
    const char character = argument[i];
    const bool letter = (character >= 'a' && character <= 'z') ||
                        (character >= 'A' && character <= 'Z');
    const bool symbol = (character >= '0' && character <= '9') ||
                        character == '+' || character == '-' ||
                        character == '.';
    if (!letter && (i == 0 || !symbol)) {
      return false;
    }
  }
  return true;
}

void ForwardToRunningInstance(const std::wstring& executable,
                              const std::vector<std::string>& arguments) {
  InstanceSearch search;
  search.executable = executable;
  for (int attempt = 0; attempt < kInstanceLookupAttempts; ++attempt) {
    EnumWindows(FindInstanceWindow, reinterpret_cast<LPARAM>(&search));
    if (search.window != nullptr) {
      break;
    }
    Sleep(kInstanceLookupDelayMs);
  }
  if (search.window == nullptr) {
    return;
  }

  AllowSetForegroundWindow(search.process_id);

  if (arguments.size() == 1 && IsLinkArgument(arguments.front())) {
    const std::string& link = arguments.front();
    COPYDATASTRUCT link_data{};
    link_data.dwData = kAppLinkMessage;
    link_data.cbData = static_cast<DWORD>(link.size() + 1);
    link_data.lpData = const_cast<char*>(link.c_str());
    SendMessageTimeoutW(search.window, WM_COPYDATA, 0,
                        reinterpret_cast<LPARAM>(&link_data), SMTO_ABORTIFHUNG,
                        kForwardTimeoutMs, nullptr);
  }

  for (const std::string& argument : arguments) {
    if (argument == kMinimizedArgument) {
      return;
    }
  }

  COPYDATASTRUCT activate_data{};
  activate_data.dwData = kActivateInstanceMessage;
  SendMessageTimeoutW(search.window, WM_COPYDATA, 0,
                      reinterpret_cast<LPARAM>(&activate_data),
                      SMTO_ABORTIFHUNG, kForwardTimeoutMs, nullptr);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  ::SetCurrentProcessExplicitAppUserModelID(kAppUserModelId);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  const std::wstring executable = ProcessImagePath(::GetCurrentProcess());
  HANDLE instance_mutex = nullptr;
  if (!executable.empty()) {
    instance_mutex =
        ::CreateMutexW(nullptr, FALSE, InstanceMutexName(executable).c_str());
    if (instance_mutex != nullptr &&
        ::GetLastError() == ERROR_ALREADY_EXISTS) {
      ForwardToRunningInstance(executable, command_line_arguments);
      ::CloseHandle(instance_mutex);
      return EXIT_SUCCESS;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  bool start_hidden = false;
  for (const std::string& argument : command_line_arguments) {
    if (argument == kMinimizedArgument) {
      start_hidden = true;
    }
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  window.SetStartHidden(start_hidden);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"ProMax", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex != nullptr) {
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}

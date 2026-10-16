#include "process_hardening.h"

#include <windows.h>

namespace {

constexpr wchar_t kSandboxKey[] = L"Software\\ProMax\\Sandbox";
constexpr wchar_t kStrictProcessValue[] = L"StrictProcess";

bool IsSeparator(wchar_t c) { return c == L'\\' || c == L'/'; }

bool StartsWith(const wchar_t* text, const wchar_t* prefix) {
  for (; *prefix != L'\0'; ++text, ++prefix) {
    if (*text != *prefix) {
      return false;
    }
  }
  return true;
}

bool RunsFromRemoteLocation() {
  wchar_t path[MAX_PATH * 4] = {};
  const DWORD capacity = static_cast<DWORD>(ARRAYSIZE(path));
  const DWORD length = ::GetModuleFileNameW(nullptr, path, capacity);
  if (length == 0 || length >= capacity) {
    return true;
  }
  const wchar_t* local = path;
  if (StartsWith(path, L"\\\\?\\UNC\\")) {
    return true;
  }
  if (StartsWith(path, L"\\\\?\\")) {
    local = path + 4;
  } else if (IsSeparator(path[0]) && IsSeparator(path[1])) {
    return true;
  }
  if (local[0] == L'\0' || local[1] != L':') {
    return true;
  }
  const wchar_t root[] = {local[0], L':', L'\\', L'\0'};
  return ::GetDriveTypeW(root) == DRIVE_REMOTE;
}

bool StrictProcessRequested() {
  DWORD value = 0;
  DWORD size = sizeof(value);
  const LSTATUS status =
      ::RegGetValueW(HKEY_CURRENT_USER, kSandboxKey, kStrictProcessValue,
                     RRF_RT_REG_DWORD, nullptr, &value, &size);
  return status == ERROR_SUCCESS && value == 1;
}

void RestrictDllSearchPath() {
  ::SetDllDirectoryW(L"");
  ::SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
}

void RestrictImageSources() {
  PROCESS_MITIGATION_IMAGE_LOAD_POLICY policy = {};
  policy.NoRemoteImages = 1;
  policy.NoLowMandatoryLabelImages = 1;
  ::SetProcessMitigationPolicy(ProcessImageLoadPolicy, &policy,
                               sizeof(policy));
}

void DisableExtensionPoints() {
  PROCESS_MITIGATION_EXTENSION_POINT_DISABLE_POLICY policy = {};
  policy.DisableExtensionPoints = 1;
  ::SetProcessMitigationPolicy(ProcessExtensionPointDisablePolicy, &policy,
                               sizeof(policy));
}

}  // namespace

void HardenProcess() {
  RestrictDllSearchPath();
  if (!RunsFromRemoteLocation()) {
    RestrictImageSources();
  }
  if (StrictProcessRequested()) {
    DisableExtensionPoints();
  }
}

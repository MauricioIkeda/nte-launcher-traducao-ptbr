#include "official_launcher_automation.h"

#include <windows.h>
#include <shellapi.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <string>
#include <thread>

namespace {

constexpr char kReadyMarker[] = "all ready, wait for start game";
constexpr char kStartedMarker[] = "GameClientAgent::launchGame]  start game";
constexpr char kLauncherPrefix[] = "--official-launcher-hex=";
constexpr char kInternalPrefix[] = "--internal-launcher-hex=";
constexpr char kLogPrefix[] = "--official-log-hex=";

int HexDigit(char value) {
  if (value >= '0' && value <= '9') {
    return value - '0';
  }
  if (value >= 'a' && value <= 'f') {
    return value - 'a' + 10;
  }
  if (value >= 'A' && value <= 'F') {
    return value - 'A' + 10;
  }
  return -1;
}

std::wstring DecodeHexUtf8(const std::string& value) {
  if (value.empty() || value.size() % 2 != 0 || value.size() > 65534) {
    return {};
  }
  std::string utf8;
  utf8.reserve(value.size() / 2);
  for (size_t index = 0; index < value.size(); index += 2) {
    const int high = HexDigit(value[index]);
    const int low = HexDigit(value[index + 1]);
    if (high < 0 || low < 0) {
      return {};
    }
    utf8.push_back(static_cast<char>((high << 4) | low));
  }
  const int length = ::MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), static_cast<int>(utf8.size()),
      nullptr, 0);
  if (length <= 0) {
    return {};
  }
  std::wstring wide(length, L'\0');
  if (::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                            static_cast<int>(utf8.size()), wide.data(),
                            length) != length) {
    return {};
  }
  return wide;
}

std::wstring ReadEncodedPath(const std::vector<std::string>& arguments,
                             const char* prefix) {
  const std::string wanted(prefix);
  for (const std::string& argument : arguments) {
    if (argument.rfind(wanted, 0) == 0) {
      return DecodeHexUtf8(argument.substr(wanted.size()));
    }
  }
  return {};
}

std::wstring FullPath(const std::wstring& path) {
  const DWORD size = ::GetFullPathNameW(path.c_str(), 0, nullptr, nullptr);
  if (size == 0 || size > 32768) {
    return {};
  }
  std::wstring result(size, L'\0');
  const DWORD copied =
      ::GetFullPathNameW(path.c_str(), size, result.data(), nullptr);
  if (copied == 0 || copied >= size) {
    return {};
  }
  result.resize(copied);
  return result;
}

std::wstring FileName(const std::wstring& path) {
  const size_t separator = path.find_last_of(L"\\/");
  return separator == std::wstring::npos ? path : path.substr(separator + 1);
}

std::wstring ParentDirectory(const std::wstring& path) {
  const size_t separator = path.find_last_of(L"\\/");
  return separator == std::wstring::npos ? L"" : path.substr(0, separator);
}

bool EqualsIgnoreCase(const std::wstring& first, const std::wstring& second) {
  return first.size() == second.size() &&
         ::CompareStringOrdinal(first.c_str(), static_cast<int>(first.size()),
                                second.c_str(), static_cast<int>(second.size()),
                                TRUE) == CSTR_EQUAL;
}

bool IsRegularFile(const std::wstring& path) {
  const DWORD attributes = ::GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool HasExpectedPaths(const std::wstring& launcher,
                      const std::wstring& internal,
                      const std::wstring& log) {
  const std::wstring launcher_name = FileName(launcher);
  const bool valid_launcher =
      EqualsIgnoreCase(launcher_name, L"NTEGlobalLauncher.exe") ||
      EqualsIgnoreCase(launcher_name, L"NTE Global Launcher.exe");
  const std::wstring internal_directory = ParentDirectory(internal);
  const std::wstring launcher_directory = ParentDirectory(launcher);
  const bool related_installation =
      EqualsIgnoreCase(launcher_directory, internal_directory) ||
      EqualsIgnoreCase(launcher_directory,
                       ParentDirectory(internal_directory));
  const std::wstring expected_log =
      FullPath(internal_directory + L"\\UserData\\Log\\NTEGlobalGame.log");
  return valid_launcher && related_installation &&
         EqualsIgnoreCase(log, expected_log) &&
         EqualsIgnoreCase(FileName(internal), L"NTEGlobalGame.exe") &&
         EqualsIgnoreCase(FileName(log), L"NTEGlobalGame.log") &&
         IsRegularFile(launcher) && IsRegularFile(internal);
}

uint64_t FileSizeOrZero(const std::wstring& path) {
  WIN32_FILE_ATTRIBUTE_DATA data = {};
  if (!::GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) {
    return 0;
  }
  ULARGE_INTEGER size = {};
  size.HighPart = data.nFileSizeHigh;
  size.LowPart = data.nFileSizeLow;
  return size.QuadPart;
}

void ReadAppendedLog(const std::wstring& path,
                     uint64_t* offset,
                     std::string* output) {
  HANDLE file = ::CreateFileW(path.c_str(), GENERIC_READ,
                              FILE_SHARE_READ | FILE_SHARE_WRITE |
                                  FILE_SHARE_DELETE,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                              nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }

  LARGE_INTEGER size = {};
  if (!::GetFileSizeEx(file, &size)) {
    ::CloseHandle(file);
    return;
  }
  if (static_cast<uint64_t>(size.QuadPart) < *offset) {
    *offset = 0;
  }

  LARGE_INTEGER position = {};
  position.QuadPart = static_cast<LONGLONG>(*offset);
  if (!::SetFilePointerEx(file, position, nullptr, FILE_BEGIN)) {
    ::CloseHandle(file);
    return;
  }

  char buffer[8192];
  DWORD read = 0;
  while (::ReadFile(file, buffer, sizeof(buffer), &read, nullptr) && read > 0) {
    output->append(buffer, read);
    *offset += read;
    if (output->size() > 1024 * 1024) {
      output->erase(0, output->size() - (512 * 1024));
    }
  }
  ::CloseHandle(file);
}

struct WindowSearch {
  std::wstring expected_path;
  HWND window = nullptr;
};

BOOL CALLBACK FindLauncherWindow(HWND window, LPARAM parameter) {
  auto* search = reinterpret_cast<WindowSearch*>(parameter);
  if (!::IsWindowVisible(window) || ::GetWindow(window, GW_OWNER) != nullptr) {
    return TRUE;
  }

  DWORD process_id = 0;
  ::GetWindowThreadProcessId(window, &process_id);
  if (process_id == 0) {
    return TRUE;
  }
  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (process == nullptr) {
    return TRUE;
  }
  std::wstring path(32768, L'\0');
  DWORD size = static_cast<DWORD>(path.size());
  const BOOL queried = ::QueryFullProcessImageNameW(process, 0, path.data(), &size);
  ::CloseHandle(process);
  if (!queried) {
    return TRUE;
  }
  path.resize(size);
  if (EqualsIgnoreCase(FullPath(path), search->expected_path)) {
    search->window = window;
    return FALSE;
  }
  return TRUE;
}

HWND FindOfficialLauncherWindow(const std::wstring& internal_path) {
  WindowSearch search{FullPath(internal_path), nullptr};
  ::EnumWindows(FindLauncherWindow, reinterpret_cast<LPARAM>(&search));
  return search.window;
}

bool ClickPlay(HWND window) {
  RECT client = {};
  if (!::GetClientRect(window, &client)) {
    return false;
  }
  const int width = client.right - client.left;
  const int height = client.bottom - client.top;
  const double aspect_ratio =
      height > 0 ? static_cast<double>(width) / height : 0.0;
  if (width < 800 || height < 500 || aspect_ratio < 1.6 ||
      aspect_ratio > 1.9) {
    return false;
  }

  // The official NTE launcher is a fixed-aspect Qt surface. Ratios keep the
  // Play button target stable under Windows display scaling.
  const int x = static_cast<int>(width * 0.875);
  const int y = static_cast<int>(height * 0.885);
  const LPARAM point = MAKELPARAM(x, y);
  if (!::PostMessageW(window, WM_LBUTTONDOWN, MK_LBUTTON, point)) {
    return false;
  }
  std::this_thread::sleep_for(std::chrono::milliseconds(80));
  return ::PostMessageW(window, WM_LBUTTONUP, 0, point) != FALSE;
}

bool LaunchOfficialLauncher(const std::wstring& launcher) {
  SHELLEXECUTEINFOW execute = {};
  execute.cbSize = sizeof(execute);
  execute.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI;
  execute.lpFile = launcher.c_str();
  const std::wstring working_directory = ParentDirectory(launcher);
  execute.lpDirectory = working_directory.c_str();
  execute.nShow = SW_SHOWNORMAL;
  if (!::ShellExecuteExW(&execute)) {
    return false;
  }
  if (execute.hProcess != nullptr) {
    ::CloseHandle(execute.hProcess);
  }
  return true;
}

}  // namespace

int RunOfficialLauncherAutomation(
    const std::vector<std::string>& command_line_arguments) {
  const std::wstring launcher =
      FullPath(ReadEncodedPath(command_line_arguments, kLauncherPrefix));
  const std::wstring internal =
      FullPath(ReadEncodedPath(command_line_arguments, kInternalPrefix));
  const std::wstring log =
      FullPath(ReadEncodedPath(command_line_arguments, kLogPrefix));
  if (launcher.empty() || internal.empty() || log.empty() ||
      !HasExpectedPaths(launcher, internal, log)) {
    return 10;
  }

  uint64_t log_offset = FileSizeOrZero(log);
  if (!LaunchOfficialLauncher(launcher)) {
    return 11;
  }

  std::string appended_log;
  HWND launcher_window = nullptr;
  const auto ready_deadline =
      std::chrono::steady_clock::now() + std::chrono::minutes(10);
  while (std::chrono::steady_clock::now() < ready_deadline) {
    ReadAppendedLog(log, &log_offset, &appended_log);
    if (launcher_window == nullptr || !::IsWindow(launcher_window)) {
      launcher_window = FindOfficialLauncherWindow(internal);
    }
    if (launcher_window != nullptr &&
        appended_log.find(kReadyMarker) != std::string::npos) {
      break;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(400));
  }

  if (launcher_window == nullptr ||
      appended_log.find(kReadyMarker) == std::string::npos) {
    return 12;
  }
  if (!ClickPlay(launcher_window)) {
    return 13;
  }

  const auto start_deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(30);
  while (std::chrono::steady_clock::now() < start_deadline) {
    ReadAppendedLog(log, &log_offset, &appended_log);
    if (appended_log.find(kStartedMarker) != std::string::npos) {
      return 0;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(250));
  }
  return 14;
}

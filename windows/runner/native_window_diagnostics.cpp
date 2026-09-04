#include "native_window_diagnostics.h"

#include <cstdio>
#include <sstream>
#include <string>

namespace NativeWindowDiagnostics {
namespace {

constexpr LONGLONG kMaximumBytes = 256 * 1024;
constexpr wchar_t kFileName[] = L"nte-translation-launcher-window.jsonl";

bool g_initialized = false;
bool g_wine_detected = false;
int g_show_command = 0;
std::string g_wine_version;
std::string g_session_id;
std::wstring g_file_path;

std::string JsonEscape(const std::string& value) {
  std::ostringstream out;
  for (unsigned char ch : value) {
    switch (ch) {
      case '\\':
        out << "\\\\";
        break;
      case '"':
        out << "\\\"";
        break;
      case '\b':
        out << "\\b";
        break;
      case '\f':
        out << "\\f";
        break;
      case '\n':
        out << "\\n";
        break;
      case '\r':
        out << "\\r";
        break;
      case '\t':
        out << "\\t";
        break;
      default:
        if (ch < 0x20) {
          char escaped[7]{};
          std::snprintf(escaped, sizeof(escaped), "\\u%04x", ch);
          out << escaped;
        } else {
          out << static_cast<char>(ch);
        }
    }
  }
  return out.str();
}

std::string UtcNow() {
  SYSTEMTIME time{};
  ::GetSystemTime(&time);
  char buffer[40]{};
  std::snprintf(buffer, sizeof(buffer),
                "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ", time.wYear,
                time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond,
                time.wMilliseconds);
  return buffer;
}

std::wstring ResolveFilePath() {
  wchar_t temp_path[MAX_PATH + 1]{};
  const DWORD length = ::GetTempPathW(MAX_PATH, temp_path);
  if (length == 0 || length > MAX_PATH) {
    return kFileName;
  }
  return std::wstring(temp_path, length) + kFileName;
}

void DetectWine() {
  HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
  if (ntdll == nullptr) {
    return;
  }
  using WineGetVersion = const char* (*)();
  auto wine_get_version = reinterpret_cast<WineGetVersion>(
      ::GetProcAddress(ntdll, "wine_get_version"));
  if (wine_get_version == nullptr) {
    return;
  }
  g_wine_detected = true;
  const char* version = wine_get_version();
  if (version != nullptr) {
    g_wine_version = version;
  }
}

void AppendWindowState(std::ostringstream& out, const char* key, HWND window) {
  out << "\"" << key << "\":";
  if (window == nullptr || !::IsWindow(window)) {
    out << "null";
    return;
  }

  RECT rect{};
  const bool has_rect = ::GetWindowRect(window, &rect) != FALSE;
  const LONG_PTR style = ::GetWindowLongPtrW(window, GWL_STYLE);
  out << "{"
      << "\"visible\":" << (::IsWindowVisible(window) ? "true" : "false")
      << ",\"iconic\":" << (::IsIconic(window) ? "true" : "false")
      << ",\"zoomed\":" << (::IsZoomed(window) ? "true" : "false")
      << ",\"foreground\":"
      << (::GetForegroundWindow() == window ? "true" : "false")
      << ",\"style\":" << static_cast<unsigned long long>(style);
  if (has_rect) {
    out << ",\"rect\":{" << "\"left\":" << rect.left
        << ",\"top\":" << rect.top << ",\"right\":" << rect.right
        << ",\"bottom\":" << rect.bottom << "}";
  }
  out << "}";
}

void AppendLine(const std::string& line) {
  if (g_file_path.empty()) {
    return;
  }

  HANDLE file = ::CreateFileW(
      g_file_path.c_str(), FILE_APPEND_DATA,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
      OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }

  LARGE_INTEGER size{};
  if (::GetFileSizeEx(file, &size) && size.QuadPart > kMaximumBytes) {
    ::CloseHandle(file);
    file = ::CreateFileW(g_file_path.c_str(), GENERIC_WRITE,
                         FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                         nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
      return;
    }
    ::CloseHandle(file);
    file = ::CreateFileW(
        g_file_path.c_str(), FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
        OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
      return;
    }
  }

  DWORD written = 0;
  ::WriteFile(file, line.data(), static_cast<DWORD>(line.size()), &written,
              nullptr);
  ::FlushFileBuffers(file);
  ::CloseHandle(file);
}

}  // namespace

void Initialize(int show_command) {
  if (g_initialized) {
    return;
  }
  g_initialized = true;
  g_show_command = show_command;
  g_file_path = ResolveFilePath();
  DetectWine();

  SYSTEMTIME time{};
  ::GetSystemTime(&time);
  char session[96]{};
  std::snprintf(session, sizeof(session),
                "%04u%02u%02uT%02u%02u%02u%03uZ-%lu", time.wYear,
                time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond,
                time.wMilliseconds, ::GetCurrentProcessId());
  g_session_id = session;
  Record("native_process_started");
}

bool IsWine() {
  return g_wine_detected;
}

void Record(const char* event, HWND top_level, HWND child) {
  if (!g_initialized || event == nullptr) {
    return;
  }

  std::ostringstream out;
  out << "{"
      << "\"at\":\"" << UtcNow() << "\""
      << ",\"source\":\"nativeWindow\""
      << ",\"sessionId\":\"" << JsonEscape(g_session_id) << "\""
      << ",\"processId\":" << ::GetCurrentProcessId()
      << ",\"event\":\"" << JsonEscape(event) << "\""
      << ",\"showCommand\":" << g_show_command
      << ",\"wineDetected\":" << (g_wine_detected ? "true" : "false")
      << ",\"wineVersion\":";
  if (g_wine_version.empty()) {
    out << "null";
  } else {
    out << "\"" << JsonEscape(g_wine_version) << "\"";
  }
  out << ",";
  AppendWindowState(out, "topLevel", top_level);
  out << ",";
  AppendWindowState(out, "flutterChild", child);
  out << "}\n";
  AppendLine(out.str());
}

}  // namespace NativeWindowDiagnostics

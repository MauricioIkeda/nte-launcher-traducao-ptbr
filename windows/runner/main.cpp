#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "native_window_diagnostics.h"
#include "official_launcher_automation.h"
#include "utils.h"

namespace {
constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\{81100993-B692-4FCC-BA9D-0A1DC3A9C33E}-NTE-Launcher-PTBR";
constexpr wchar_t kLauncherWindowTitle[] =
    L"NTE Launcher Tradu\u00e7\u00e3o PT-BR";
constexpr DWORD kInstallHandoffTimeoutMs = 15000;

void ActivateExistingLauncherWindow() {
  HWND window = ::FindWindowW(nullptr, kLauncherWindowTitle);
  if (window == nullptr) {
    return;
  }
  if (::IsIconic(window)) {
    ::ShowWindow(window, SW_RESTORE);
  } else {
    ::ShowWindow(window, SW_SHOW);
  }
  ::SetForegroundWindow(window);
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  if (std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--official-ready-play") != command_line_arguments.end()) {
    return RunOfficialLauncherAutomation(command_line_arguments);
  }

  const bool elevated_install =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--install") != command_line_arguments.end();
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (elevated_install) {
      const DWORD wait_result =
          ::WaitForSingleObject(single_instance_mutex, kInstallHandoffTimeoutMs);
      if (wait_result != WAIT_OBJECT_0 && wait_result != WAIT_ABANDONED) {
        ::CloseHandle(single_instance_mutex);
        return EXIT_FAILURE;
      }
    } else {
      ActivateExistingLauncherWindow();
      ::CloseHandle(single_instance_mutex);
      return EXIT_SUCCESS;
    }
  }

  NativeWindowDiagnostics::Initialize(show_command);

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  const std::wstring executable_directory = GetExecutableDirectory();
  if (executable_directory.empty() ||
      !::SetCurrentDirectoryW(executable_directory.c_str())) {
    NativeWindowDiagnostics::Record("set_current_directory_failed");
    ::CoUninitialize();
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_FAILURE;
  }
  flutter::DartProject project(executable_directory + L"\\data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  NativeWindowDiagnostics::Record("window_create_requested");
  if (!window.Create(kLauncherWindowTitle, origin, size)) {
    NativeWindowDiagnostics::Record("window_create_failed", window.GetHandle());
    ::CoUninitialize();
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);
  NativeWindowDiagnostics::Record("window_create_completed", window.GetHandle());

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  NativeWindowDiagnostics::Record("message_loop_exited", window.GetHandle());
  ::CoUninitialize();
  if (single_instance_mutex != nullptr) {
    ::CloseHandle(single_instance_mutex);
  }
  return EXIT_SUCCESS;
}

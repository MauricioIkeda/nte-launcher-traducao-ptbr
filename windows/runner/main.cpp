#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "native_window_diagnostics.h"
#include "official_launcher_automation.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  if (std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--official-ready-play") != command_line_arguments.end()) {
    return RunOfficialLauncherAutomation(command_line_arguments);
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
    return EXIT_FAILURE;
  }
  flutter::DartProject project(executable_directory + L"\\data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  NativeWindowDiagnostics::Record("window_create_requested");
  if (!window.Create(L"NTE Launcher Tradu\u00e7\u00e3o PT-BR", origin, size)) {
    NativeWindowDiagnostics::Record("window_create_failed", window.GetHandle());
    ::CoUninitialize();
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
  return EXIT_SUCCESS;
}

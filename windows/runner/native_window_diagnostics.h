#ifndef RUNNER_NATIVE_WINDOW_DIAGNOSTICS_H_
#define RUNNER_NATIVE_WINDOW_DIAGNOSTICS_H_

#include <windows.h>

namespace NativeWindowDiagnostics {

// Starts a small, persistent and privacy-safe native window black box. The
// file lives in the Wine/Windows temp directory so a later successful launcher
// session can still include evidence from an earlier invisible-window session.
void Initialize(int show_command);

// True when ntdll exposes Wine's runtime version entry point.
bool IsWine();

// Records a bounded JSONL event with top-level and Flutter child window state.
// No user paths, titles, command lines, account data or secrets are written.
void Record(const char* event, HWND top_level = nullptr, HWND child = nullptr);

}  // namespace NativeWindowDiagnostics

#endif  // RUNNER_NATIVE_WINDOW_DIAGNOSTICS_H_

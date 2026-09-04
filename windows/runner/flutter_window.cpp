#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "native_window_diagnostics.h"

namespace {

constexpr UINT_PTR kStartupVisibilityTimer = 1;
constexpr UINT kStartupVisibilityTimeoutMs = 3000;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    NativeWindowDiagnostics::Record("win32_on_create_failed", GetHandle());
    return false;
  }
  NativeWindowDiagnostics::Record("win32_on_create_completed", GetHandle());

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    NativeWindowDiagnostics::Record("flutter_controller_create_failed",
                                    GetHandle());
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  HWND flutter_child = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(flutter_child);
  NativeWindowDiagnostics::Record("flutter_child_attached", GetHandle(),
                                  flutter_child);

  // Normally the top-level window is shown only after Flutter renders its
  // first frame, avoiding a blank startup flash. Wine/Proton can occasionally
  // report the Win32 window as visible before the Linux compositor actually
  // presents it. Keep the normal Windows path, but under Wine show early and
  // retain a one-shot reconciliation after the first frame.
  const UINT_PTR timer = ::SetTimer(GetHandle(), kStartupVisibilityTimer,
                                    kStartupVisibilityTimeoutMs, nullptr);
  NativeWindowDiagnostics::Record(
      timer == 0 ? "startup_visibility_timer_arm_failed"
                 : "startup_visibility_timer_armed",
      GetHandle(), flutter_child);

  if (NativeWindowDiagnostics::IsWine()) {
    Show();
    if (flutter_child != nullptr) {
      ::ShowWindow(flutter_child, SW_SHOWNA);
    }
    NativeWindowDiagnostics::Record("wine_immediate_show", GetHandle(),
                                    flutter_child);
  }

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    HWND child = flutter_controller_ && flutter_controller_->view()
                     ? flutter_controller_->view()->GetNativeWindow()
                     : nullptr;
    NativeWindowDiagnostics::Record("first_frame_callback", GetHandle(),
                                    child);

    // On native Windows the first frame remains the success condition for the
    // startup watchdog. Under Wine, keep the timer alive for one additional
    // reconciliation because ShowWindow/WS_VISIBLE does not guarantee that a
    // Wayland/XWayland compositor has presented the surface.
    if (!NativeWindowDiagnostics::IsWine() && GetHandle() != nullptr) {
      ::KillTimer(GetHandle(), kStartupVisibilityTimer);
    }
    Show();
    if (NativeWindowDiagnostics::IsWine() && child != nullptr) {
      ::ShowWindow(child, SW_SHOWNA);
    }
    NativeWindowDiagnostics::Record("first_frame_show_completed", GetHandle(),
                                    child);
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();
  NativeWindowDiagnostics::Record("initial_force_redraw", GetHandle(),
                                  flutter_child);

  return true;
}

void FlutterWindow::OnDestroy() {
  HWND child = flutter_controller_ && flutter_controller_->view()
                   ? flutter_controller_->view()->GetNativeWindow()
                   : nullptr;
  NativeWindowDiagnostics::Record("window_destroy_started", GetHandle(), child);
  if (GetHandle() != nullptr) {
    ::KillTimer(GetHandle(), kStartupVisibilityTimer);
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_TIMER && wparam == kStartupVisibilityTimer) {
    ::KillTimer(hwnd, kStartupVisibilityTimer);
    HWND child = flutter_controller_ && flutter_controller_->view()
                     ? flutter_controller_->view()->GetNativeWindow()
                     : nullptr;
    NativeWindowDiagnostics::Record("startup_visibility_timer_fired", hwnd,
                                    child);

    if (NativeWindowDiagnostics::IsWine()) {
      // Do not trust IsWindowVisible as proof that the Linux compositor has
      // presented the window. Reconcile the parent and Flutter child once,
      // without stealing focus, then ask Flutter for another frame.
      ::ShowWindow(hwnd, SW_SHOWNOACTIVATE);
      ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                         SWP_SHOWWINDOW);
      if (child != nullptr) {
        RECT frame = GetClientArea();
        ::ShowWindow(child, SW_SHOWNA);
        ::MoveWindow(child, frame.left, frame.top, frame.right - frame.left,
                     frame.bottom - frame.top, TRUE);
      }
      ::RedrawWindow(hwnd, nullptr, nullptr,
                     RDW_INVALIDATE | RDW_UPDATENOW | RDW_ALLCHILDREN |
                         RDW_FRAME);
      if (flutter_controller_) {
        flutter_controller_->ForceRedraw();
      }
      NativeWindowDiagnostics::Record("wine_visibility_reconciled", hwnd,
                                      child);
    } else if (!::IsWindowVisible(hwnd)) {
      Show();
      NativeWindowDiagnostics::Record("native_visibility_fallback_show", hwnd,
                                      child);
    } else {
      NativeWindowDiagnostics::Record("native_visibility_already_visible", hwnd,
                                      child);
    }
    return 0;
  }

  if (message == WM_SHOWWINDOW) {
    HWND child = flutter_controller_ && flutter_controller_->view()
                     ? flutter_controller_->view()->GetNativeWindow()
                     : nullptr;
    NativeWindowDiagnostics::Record(
        wparam != 0 ? "wm_showwindow_visible" : "wm_showwindow_hidden", hwnd,
        child);
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

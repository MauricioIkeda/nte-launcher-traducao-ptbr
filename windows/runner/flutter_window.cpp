#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr UINT_PTR kStartupVisibilityTimer = 1;
constexpr UINT kStartupVisibilityTimeoutMs = 3000;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

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

  // Normally the top-level window is shown only after Flutter renders its
  // first frame, avoiding a blank startup flash. Wine/Proton can occasionally
  // delay that frame while a platform channel is initializing, leaving a live
  // process with no visible window. Keep the normal path, but never remain
  // invisible indefinitely.
  ::SetTimer(GetHandle(), kStartupVisibilityTimer,
             kStartupVisibilityTimeoutMs, nullptr);

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    if (GetHandle() != nullptr) {
      ::KillTimer(GetHandle(), kStartupVisibilityTimer);
    }
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
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
    if (!::IsWindowVisible(hwnd)) {
      Show();
    }
    return 0;
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

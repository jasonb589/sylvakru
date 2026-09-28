#include "flutter_window.h"

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

namespace {

/* The method channel carries UTF-8; the Windows API wants UTF-16. */
std::wstring WideFromUtf8(const std::string &text) {
  if (text.empty()) {
    return std::wstring();
  }
  const int length = static_cast<int>(text.size());
  const int size =
      MultiByteToWideChar(CP_UTF8, 0, text.c_str(), length, nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.c_str(), length, wide.data(), size);
  return wide;
}

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

  /* Free space is the one question Dart cannot answer for itself, so the app
     asks the platform. The channel lives as long as the window does. */
  disk_space_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "sylvakru/disk_space",
          &flutter::StandardMethodCodec::GetInstance());
  disk_space_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue> &call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "freeSpace") {
          result->NotImplemented();
          return;
        }
        std::wstring path;
        if (const auto *arguments =
                std::get_if<flutter::EncodableMap>(call.arguments())) {
          const auto entry = arguments->find(flutter::EncodableValue("path"));
          if (entry != arguments->end()) {
            if (const auto *value = std::get_if<std::string>(&entry->second)) {
              path = WideFromUtf8(*value);
            }
          }
        }
        ULARGE_INTEGER free_bytes{};
        ULARGE_INTEGER total_bytes{};
        ULARGE_INTEGER total_free_bytes{};
        BOOL answered = GetDiskFreeSpaceExW(path.c_str(), &free_bytes,
                                            &total_bytes, &total_free_bytes);
        /* A downloads folder that is not there yet still sits on a volume: the
           root of the path answers for it just as well. */
        if (!answered && path.size() > 3) {
          answered = GetDiskFreeSpaceExW(path.substr(0, 3).c_str(), &free_bytes,
                                         &total_bytes, &total_free_bytes);
        }
        if (!answered) {
          /* Unknown rather than zero: a zero would read as a full disk. */
          result->Success(flutter::EncodableValue());
          return;
        }
        result->Success(flutter::EncodableValue(
            static_cast<int64_t>(free_bytes.QuadPart)));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    auto *registry = flutter_view_controller->engine();
    RegisterPlugins(registry);
  });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
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

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

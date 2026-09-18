#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// Unique per-app name for the single-instance mutex. Session-local (no
// "Global\" prefix) so it enforces one instance per Windows user session,
// which is what a POS terminal needs; change to L"Global\\..." to block a
// second instance across ALL sessions (e.g. multiple RDP users) on the box.
constexpr const wchar_t kSingleInstanceMutexName[] =
    L"caisse212_pos_single_instance";

// The Flutter runner's window class (see win32_window.cpp). Used to locate an
// already-running instance's window even if its title was changed at runtime
// (e.g. by the window_manager plugin).
constexpr const wchar_t kRunnerWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // ── Single-instance guard ────────────────────────────────────────────────
  // Create a named mutex. The first instance owns it for its whole lifetime;
  // the OS keeps the mutex alive while the handle is open. A second launch sees
  // ERROR_ALREADY_EXISTS, brings the existing window to the foreground, and
  // exits — so only one copy of the POS ever runs at a time.
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  // Only bail when a valid mutex already existed (another instance owns it).
  // If CreateMutexW itself failed (null, very rare), fall through and start
  // anyway — a POS must never refuse to launch over a mutex hiccup; single
  // instance is simply not enforced that run.
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Focus the already-running window (best-effort), then bail out.
    HWND existing = ::FindWindowW(kRunnerWindowClass, nullptr);
    if (existing != nullptr) {
      if (::IsIconic(existing)) {
        ::ShowWindow(existing, SW_RESTORE);
      }
      ::SetForegroundWindow(existing);
    }
    ::CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
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

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"CAISSE212", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  // Release the single-instance mutex on a clean exit so the next launch can
  // start immediately. (Windows also drops it automatically when the process
  // dies, covering crashes.)
  if (single_instance_mutex != nullptr) {
    ::ReleaseMutex(single_instance_mutex);
    ::CloseHandle(single_instance_mutex);
  }
  return EXIT_SUCCESS;
}

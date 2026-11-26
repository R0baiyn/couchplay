#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
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
  if (!window.Create(L"CouchPlay", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Parcours de test (integration_test) seulement : fenêtre hors de l'écran,
  // sans focus ni bouton dans la barre des tâches. Ni masquée ni réduite :
  // Flutter cesserait de dessiner. Un plein écran la ramènerait à l'écran.
  if (::GetEnvironmentVariable(L"COUCHPLAY_TEST_HIDDEN", nullptr, 0) != 0) {
    HWND handle = window.GetHandle();
    ::SetWindowLongPtr(handle, GWL_EXSTYLE,
                       ::GetWindowLongPtr(handle, GWL_EXSTYLE) |
                           WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
    ::SetWindowPos(handle, nullptr, -32000, -32000, 0, 0,
                   SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}

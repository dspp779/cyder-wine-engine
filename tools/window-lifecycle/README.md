# Isolated window lifecycle controls

`ax-window-cycle.swift` validates an explicitly observed host PID, CGWindow ID
and exact unique AX title. It changes only AXMinimized / AXFullScreen on that
target, polls the actual state, and requires the same visible window and original
geometry after restoration. Output omits titles and credentials. No Win32
restore fallback, keyboard input, Dock automation or global process termination
is hidden in a passing result.

```sh
swiftc -module-cache-path /private/tmp/cyder-ax-module-cache \
  tools/window-lifecycle/ax-window-cycle.swift -o /private/tmp/ax-window-cycle
/private/tmp/ax-window-cycle HOST_PID WINDOW_ID 'EXACT_TITLE' \
  --cycles 3 --fullscreen-cycles 2
```

Observe the current window and capture it first. Accessibility and Screen
Recording permission must already be granted to the host. Counts are bounded
at 20; each state/geometry wait is bounded at seven seconds. A successful AX set
alone never counts as a restored window. Do not run this against unrelated
windows or while someone else is moving the desktop.

`win32-control.c` is a credential-free GDI control, built with llvm-mingw and
run only in a disposable prefix. It logs WM_SYSCOMMAND / WM_SIZE and closes
after 180 seconds if the test has not already closed it. Compile separately for
i686 and x86_64; that timeout is a cleanup limit, not a passing test.

To close only this fixture, run the same executable with `--close` in the
same disposable prefix. It finds the fixture's unique Win32 class/title and
sends bounded WM_CLOSE; the owner logs WM_CLOSE and exits its message loop.
Verify the owner's process exit separately. The three-minute cleanup timer
prints TIMEOUT and never counts as a normal-close pass.

Keep game captures/logs private and publish only sanitized evidence. These
are developer tools, not installed runtime components or game settings.

# Mono last-error probe

`monoerr.c` checks whether a Unity Mono runtime sees the right Win32 last error
under this engine, without starting a game. It loads the game's own
`mono-2.0-bdwgc.dll` and `mscorlib`, then prints native `GetLastError()` after
`FindNextFile` and `GetFileAttributes`, managed `File.Exists(missing)`,
`Marshal.GetLastWin32Error()` and `Directory.GetFiles(existing)`.

Build with the llvm-mingw toolchain in `build/`:

```sh
build/llvm-mingw-*/bin/x86_64-w64-mingw32-clang -O1 -o monoerr.exe tools/mono-last-error-probe/monoerr.c
```

Run in a test prefix that can see a Unity Mono game (paths are Windows paths):

```sh
WINEPREFIX=<prefix> <engine>/bin/wine 'C:\monoerr.exe' '<game root>' '<existing dir>' 'C:\users\crossover\nope.priority'
```

Expected with `cyder-ntdll-mono-gs-last-error.patch`: native 18 and 2,
`File.Exists` False, `Marshal.GetLastWin32Error` 2 (not a large or negative
number). `WINEDEBUG=trace+module` shows how many sites were rewritten and
whether the JIT emitter was redirected. `CYDER_MONO_GS_LASTERROR=0` shows the
unfixed behaviour.

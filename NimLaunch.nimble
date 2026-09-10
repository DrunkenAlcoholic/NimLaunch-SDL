import std/os

# Package

packageName   = "nimlaunch"
version       = "0.11.5"
author        = "Vyrnexis"
description   = "NimLaunch in SDL3 for native X11 and Wayland"
license       = "MIT"
srcDir        = "src"
bin           = @["nimlaunch"]
binDir        = "bin"


# Dependencies

requires "nim >= 2.0"

# Build tasks

const
  EntryPoint = "src/nimlaunch.nim"
  OutBin = "-o:./bin/nimlaunch"
  NativeReleaseFlags = "-d:release -d:danger --opt:speed --passC:'-march=native -mtune=native'"
  NativeGenericFlags = "-d:release -d:danger --opt:speed --passC:'-march=x86-64 -mtune=generic'"
  NativeDebugFlags = "-d:debug --mm:orc --threads:on --debuginfo --lineTrace:on --stackTrace:on --opt:none"
  ZigReleaseBaseFlags = "-d:release -d:danger --opt:speed --cc:clang --passC:'-target x86_64-linux-gnu -mcpu=native' --passL:'-target x86_64-linux-gnu'"
  ZigGenericBaseFlags = "-d:release -d:danger --opt:speed --cc:clang --passC:'-target x86_64-linux-gnu -mcpu=x86_64' --passL:'-target x86_64-linux-gnu'"
  ZigDebugBaseFlags = "-d:debug --mm:orc --threads:on --debuginfo --lineTrace:on --stackTrace:on --opt:none --cc:clang"

# Run a Nim build with the supplied compiler flags.
proc runBuild(flags: string) =
  exec "nim c " & flags & " " & OutBin & " " & EntryPoint

# Build with the repository's Zig compiler wrapper using its absolute path.
proc runZigBuild(flags: string) =
  let zigCompiler = getCurrentDir() / "zigcc"
  let compilerFlags = " --clang.exe='" & zigCompiler &
    "' --clang.linkerexe='" & zigCompiler & "'"
  runBuild(flags & compilerFlags)

task nimRelease, "Release build optimized for current CPU (fastest local binary)":
  mkDir("bin")
  runBuild(NativeReleaseFlags)

task nimGeneric, "Release build with generic x86_64 baseline (universal)":
  mkDir("bin")
  runBuild(NativeGenericFlags)

task nimDebug, "Debug build with native compiler":
  mkDir("bin")
  runBuild(NativeDebugFlags)

# Zig-based builds (generic)
task zigRelease, "Release build with Zig compiler optimized for current CPU":
  mkDir("bin")
  runZigBuild(ZigReleaseBaseFlags)

task zigGeneric, "Release build with Zig compiler (universal)":
  mkDir("bin")
  runZigBuild(ZigGenericBaseFlags)

task zigDebug, "Debug build with Zig compiler":
  mkDir("bin")
  runZigBuild(ZigDebugBaseFlags)

task test, "Run all test suites":
  mkDir("bin")
  exec "nim c -r --nimcache:./bin/nimcache-tfuzzy -o:./bin/tfuzzy tests/tfuzzy.nim"
  exec "nim c -r --nimcache:./bin/nimcache-tparser -o:./bin/tparser tests/tparser.nim"
  exec "nim c -r --nimcache:./bin/nimcache-tconfig -o:./bin/tconfig tests/tconfig.nim"
  exec "nim c -r --nimcache:./bin/nimcache-tcache -o:./bin/tcache tests/tcache.nim"
  exec "nim c -r --nimcache:./bin/nimcache-tutils -o:./bin/tutils tests/tutils.nim"
  exec "nim c -r --nimcache:./bin/nimcache-tlogic -o:./bin/tlogic tests/tlogic.nim"

task clean, "Remove build artifacts and caches":
  rmDir("bin")
  rmDir("nimcache")

task build, "Default build": nimReleaseTask()

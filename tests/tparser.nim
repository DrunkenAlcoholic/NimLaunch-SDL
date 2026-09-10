import std/[unittest, options, os, tables]
import ../src/parser

suite "Parser tests":
  test "tokenize basic args":
    let toks = tokenize("hello world")
    check toks == @["hello", "world"]

  test "tokenize quotes":
    let toks = tokenize("cmd -arg \"hello world\" 'foo bar'")
    check toks == @["cmd", "-arg", "hello world", "foo bar"]

  test "tokenize preserves an explicitly empty argument":
    check tokenize("cmd \"\" tail") == @["cmd", "", "tail"]

  test "tokenize escapes":
    let toks = tokenize("cmd \"hello \\\"world\\\"\"")
    check toks == @["cmd", "hello \"world\""]

  test "stripFieldCodes":
    check stripFieldCodes("code %F") == "code"
    check stripFieldCodes("foo %u %i %c") == "foo"
    check stripFieldCodes("100%% sure") == "100% sure"

  test "expand Desktop Entry field codes":
    let expanded = expandExecArgs("viewer %F %i --name=%c %k %%",
        "My App", "my-icon", "/tmp/my-app.desktop")
    check expanded.valid
    check expanded.args == @[
      "viewer", "--icon", "my-icon", "--name=My App",
      "/tmp/my-app.desktop", "%"
    ]
    check not expandExecArgs("viewer %x").valid

  test "prefer localized values before the default":
    let hadLcAll = existsEnv("LC_ALL")
    let oldLcAll = getEnv("LC_ALL")
    defer:
      if hadLcAll: putEnv("LC_ALL", oldLcAll)
      else: delEnv("LC_ALL")
    putEnv("LC_ALL", "fr_FR.UTF-8")
    let entries = {
      "Name": "English",
      "Name[fr]": "Français",
      "Name[fr_FR]": "Français (France)"
    }.toTable
    check getBestValue(entries, "Name") == "Français (France)"

  test "getBaseExec":
    check getBaseExec("/usr/bin/kitty --single-instance") == "kitty"
    check getBaseExec("code %F") == "code"
    check getBaseExec("env FOO=1 VAR=2 /opt/app/bin/foo %U") == "foo"
    check getBaseExec("flatpak run com.app.Name") == "com.app.Name"
    check getBaseExec("snap run app") == "app"
    check getBaseExec("sh -c 'prog --opt'") == "prog"
    check getBaseExec("sudo nano") == "nano"
    check getBaseExec("pkexec gparted") == "gparted"

  test "parseDesktopFile valid entry with actions":
    let tmp = getTempDir() / "nimlaunch_test_valid.desktop"
    writeFile(tmp, """[Desktop Entry]
Name=SuperApp
Exec=superapp %U
Path=/tmp
Icon=superapp-icon
Categories=Network;WebBrowser;
Actions=NewTab;

[Desktop Action NewTab]
Name=New Tab
Exec=superapp --new-tab
Icon=tab-new
""")
    defer:
      if fileExists(tmp): removeFile(tmp)

    let parsed = parseDesktopFile(tmp)
    check isSome(parsed)
    let app = get(parsed)
    check app.name == "SuperApp"
    check app.exec == "superapp %U"
    check app.desktopFile == tmp
    check app.workingDir == "/tmp"
    check app.icon == "superapp-icon"
    check app.hasIcon == true
    check app.desktopActions.len == 1
    check app.desktopActions[0].id == "NewTab"
    check app.desktopActions[0].name == "New Tab"
    check app.desktopActions[0].exec == "superapp --new-tab"

  test "parseDesktopFile exclusions":
    let tmp = getTempDir() / "nimlaunch_test_excluded.desktop"
    defer:
      if fileExists(tmp): removeFile(tmp)

    # NoDisplay=true
    writeFile(tmp, "[Desktop Entry]\nName=HiddenApp\nExec=hiddenapp\nNoDisplay=true\n")
    check isNone(parseDesktopFile(tmp))

    # Terminal=true
    writeFile(tmp, "[Desktop Entry]\nName=TerminalApp\nExec=htop\nTerminal=true\n")
    check isNone(parseDesktopFile(tmp))

    # Unknown field codes invalidate the entry.
    writeFile(tmp, "[Desktop Entry]\nName=InvalidApp\nExec=invalid %x\n")
    check isNone(parseDesktopFile(tmp))

  test "categories do not control application visibility":
    let tmp = getTempDir() / "nimlaunch_test_categories.desktop"
    defer:
      if fileExists(tmp): removeFile(tmp)

    writeFile(tmp,
        "[Desktop Entry]\nName=SettingsApp\nExec=gnome-control-center\n" &
        "Categories=GNOME;GTK;Settings;\n")
    check isSome(parseDesktopFile(tmp))

    writeFile(tmp,
        "[Desktop Entry]\nName=SystemApp\nExec=system-monitor\nCategories=System;\n")
    check isSome(parseDesktopFile(tmp))

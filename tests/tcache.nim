import std/[unittest, json]
import ../src/state

suite "Cache serialization tests":
  test "CacheData json roundtrip":
    let action1 = DesktopEntryAction(
      id: "NewWindow",
      name: "New Window",
      nameLower: "new window",
      exec: "app --new-window",
      icon: "app-window",
      hasIcon: true
    )
    let app1 = DesktopApp(
      name: "Test App",
      nameLower: "test app",
      exec: "app %U",
      desktopFile: "/usr/share/applications/test-app.desktop",
      desktopId: "test-app.desktop",
      workingDir: "/tmp",
      icon: "test-app",
      hasIcon: true,
      desktopActions: @[action1]
    )
    let orig = CacheData(
      formatVersion: 8,
      environmentSignature: "test-locale-and-path",
      appDirs: @["/usr/share/applications"],
      dirMtimes: @[1700000000'i64],
      dirSignatures: @["1:1700000000:1700000000:1024:9999"],
      apps: @[app1]
    )

    let jsonStr = $ %orig
    let parsedNode = parseJson(jsonStr)
    let restored = to(parsedNode, CacheData)

    check restored.formatVersion == orig.formatVersion
    check restored.environmentSignature == orig.environmentSignature
    check restored.appDirs == orig.appDirs
    check restored.dirMtimes == orig.dirMtimes
    check restored.dirSignatures == orig.dirSignatures
    check restored.apps.len == 1

    let restoredApp = restored.apps[0]
    check restoredApp.name == "Test App"
    check restoredApp.exec == "app %U"
    check restoredApp.desktopFile == "/usr/share/applications/test-app.desktop"
    check restoredApp.desktopId == "test-app.desktop"
    check restoredApp.workingDir == "/tmp"
    check restoredApp.icon == "test-app"
    check restoredApp.hasIcon == true
    check restoredApp.desktopActions.len == 1
    check restoredApp.desktopActions[0].id == "NewWindow"
    check restoredApp.desktopActions[0].exec == "app --new-window"

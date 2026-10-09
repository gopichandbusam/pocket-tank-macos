import AppKit
import Foundation

let tankID = "com.local.pockettank"
let files = FileManager.default

func hasSymlinkAncestor(_ url: URL) -> Bool {
    var current = url.standardizedFileURL
    while current.path != "/" {
        // Foundation canonicalizes /private/var and /private/tmp to these
        // root-owned macOS aliases. User-created links below them still fail.
        if ["/var", "/tmp", "/etc"].contains(current.path) { return false }
        if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { return true }
        current.deleteLastPathComponent()
    }
    return false
}

func ownedApp(_ url: URL) -> Bool {
    guard url.pathExtension.lowercased() == "app",
          !hasSymlinkAncestor(url.appendingPathComponent("Contents/Info.plist")),
          !url.standardizedFileURL.path.hasPrefix("/System/"),
          let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
          let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    else { return false }
    return info["CFBundleIdentifier"] as? String == tankID
}

func appTargets(_ candidates: [URL]) -> [URL] {
    var seen = Set<String>()
    return candidates.map { $0.standardizedFileURL }.filter {
        seen.insert($0.path).inserted && ownedApp($0) &&
        (try? $0.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) != true
    }
}

func dataTargets(_ home: URL) -> [URL] {
    return ["Library/Application Support/Pocket Tank",
            "Library/Preferences/com.local.pockettank.plist",
            "Library/Caches/com.local.pockettank",
            "Library/Saved Application State/com.local.pockettank.savedState"]
        .map { home.appendingPathComponent($0) }
}

func available(_ urls: [URL]) -> [URL] {
    urls.filter { files.fileExists(atPath: $0.path) ||
        (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true }
}

func selfTest() throws {
    func require(_ condition: Bool, _ label: String) throws {
        if !condition { throw NSError(domain: "UninstallerSelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
    }
    let fixture = files.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("pocket-uninstall-test-\(UUID().uuidString)")
    try files.createDirectory(at: fixture, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: fixture) }
    func makeApp(_ name: String, _ identifier: String) throws -> URL {
        let app = fixture.appendingPathComponent(name)
        try files.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": identifier], format: .xml, options: 0)
        try info.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }
    let owned = try makeApp("Pocket Tank.app", tankID)
    let foreign = try makeApp("Other.app", "org.example.other")
    let symlink = fixture.appendingPathComponent("Linked.app")
    try files.createSymbolicLink(at: symlink, withDestinationURL: foreign)
    try require(appTargets([owned, foreign, symlink, owned]).map { $0.path } == [owned.path], "owned-app scope: \(appTargets([owned, foreign, symlink, owned]).map { $0.path }); expected \(owned.path)")
    let home = fixture.appendingPathComponent("home")
    let targets = dataTargets(home)
    try require(targets.count == 4 && targets.allSatisfy { $0.path.hasPrefix(home.path + "/Library/") }, "data scope")
    let unrelated = home.appendingPathComponent("Documents/keep.txt")
    try files.createDirectory(at: unrelated.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: unrelated)
    for path in targets {
        try files.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: path)
    }
    let trash = fixture.appendingPathComponent("fake-trash")
    try files.createDirectory(at: trash, withIntermediateDirectories: true)
    for (index, path) in (appTargets([owned, foreign, symlink]) + available(targets)).enumerated() {
        try files.moveItem(at: path, to: trash.appendingPathComponent(String(index)))
    }
    try require(!files.fileExists(atPath: owned.path), "owned app removed")
    try require(targets.allSatisfy { !files.fileExists(atPath: $0.path) }, "fixture data removed")
    try require(files.fileExists(atPath: foreign.path) && files.fileExists(atPath: symlink.path), "foreign and linked app preserved")
    let preserved = try Data(contentsOf: unrelated)
    try require(preserved == Data("keep".utf8), "unrelated file preserved")
    print("PASS: fixture-only uninstall scope, bundle identity, duplicates, symlink rejection, data removal and unrelated-file preservation. No real app, preferences or aquarium data changed.")
}

if CommandLine.arguments.contains("--self-test") {
    do { try selfTest(); exit(0) }
    catch { fputs("Self-test failed: \(error)\n", stderr); exit(1) }
}

let home = files.homeDirectoryForCurrentUser
let running = NSRunningApplication.runningApplications(withBundleIdentifier: tankID)
var candidates = [URL(fileURLWithPath: "/Applications/Pocket Tank.app"),
                  home.appendingPathComponent("Applications/Pocket Tank.app"),
                  Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Pocket Tank.app")]
candidates.append(contentsOf: running.compactMap { $0.bundleURL })
if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: tankID) {
    candidates.append(registered)
}
let apps = appTargets(candidates)
let data = dataTargets(home)

if CommandLine.arguments.contains("--dry-run") {
    print("READ ONLY — no app stopped and no files or preferences changed.")
    for path in apps { print("APP: \(path.path)") }
    for path in data { print("DATA: \(path.path) [\(available([path]).isEmpty ? "absent" : "present")]") }
    print("PREFERENCES DOMAIN: \(tankID)")
    exit(0)
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
application.activate(ignoringOtherApps: true)
let dialog = NSAlert()
dialog.messageText = "Uninstall Pocket Tank?"
dialog.informativeText = "Pocket Tank will save and quit. Installed copies found below will move to Trash.\n\n" +
    (apps.isEmpty ? "No installed app found." : apps.map { $0.path }.joined(separator: "\n")) +
    "\n\nThe installer DMG and source folder will stay in place."
dialog.addButton(withTitle: "Cancel")
dialog.addButton(withTitle: "Uninstall")
dialog.alertStyle = .warning
let removeData = NSButton(checkboxWithTitle: "Also remove my aquarium, fish progress and settings", target: nil, action: nil)
removeData.state = .on
removeData.frame = NSRect(x: 0, y: 0, width: 440, height: 28)
dialog.accessoryView = removeData
if CommandLine.arguments.contains("--ui-test-cancel") {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { dialog.buttons.first?.performClick(nil) }
}
guard dialog.runModal() == .alertSecondButtonReturn else { exit(0) }

let runningAtConfirmation = NSRunningApplication.runningApplications(withBundleIdentifier: tankID)
for app in runningAtConfirmation { _ = app.terminate() }
let deadline = Date().addingTimeInterval(12)
while runningAtConfirmation.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
if !NSRunningApplication.runningApplications(withBundleIdentifier: tankID).isEmpty {
    let error = NSAlert()
    error.messageText = "Pocket Tank is still running"
    error.informativeText = "No files were removed. Quit Pocket Tank and run this uninstaller again."
    error.runModal()
    exit(1)
}

var errors: [String] = []
var removed = 0
let removeSaved = removeData.state == .on
// Revalidate after confirmation, then use macOS Trash instead of recursive deletion.
let confirmedApps = appTargets(apps)
for path in confirmedApps + (removeSaved ? available(data) : []) {
    if hasSymlinkAncestor(path) {
        errors.append("\(path.path): symbolic links are left in place; no linked files were removed.")
        continue
    }
    do {
        try files.trashItem(at: path, resultingItemURL: nil)
        removed += 1
    } catch { errors.append("\(path.path): \(error.localizedDescription)") }
}
if removeSaved && errors.isEmpty {
    UserDefaults.standard.removePersistentDomain(forName: tankID)
    UserDefaults.standard.synchronize()
    // cfprefsd may recreate an empty plist after clearing its cached domain.
    for path in available([home.appendingPathComponent("Library/Preferences/com.local.pockettank.plist")]) {
        if hasSymlinkAncestor(path) {
            errors.append("\(path.path): symbolic link left in place.")
            continue
        }
        do { try files.trashItem(at: path, resultingItemURL: nil) }
        catch { errors.append("\(path.path): \(error.localizedDescription)") }
    }
}
let result = NSAlert()
result.messageText = errors.isEmpty ? "Pocket Tank uninstalled" : "Some items could not be removed"
result.informativeText = errors.isEmpty ?
    "Moved \(removed) item(s) to Trash. \(removeSaved ? "Aquarium data and settings were removed." : "Your aquarium data and settings were kept.") Empty Trash when you want to erase the removed files permanently." :
    "Items successfully removed are in Trash.\n\n" + errors.joined(separator: "\n")
result.runModal()
exit(errors.isEmpty ? 0 : 1)

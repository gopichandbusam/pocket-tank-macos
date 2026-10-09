import AppKit
import Foundation
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.local.pockettank")
for app in apps { _ = app.terminate() }
let deadline = Date().addingTimeInterval(10)
while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
if apps.contains(where: { !$0.isTerminated }) {
    fputs("Pocket Tank did not finish its normal save-and-quit; update was not installed.\n", stderr)
    exit(1)
}
print("Pocket Tank finished its normal save-and-quit.")

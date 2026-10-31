// Launch check, run by CI after `make app`: starts DockFlip.app for real and holds it to
// SCOPE.md's performance budgets. It fails when the app quits on its own, puts no window on
// screen in time, uses more memory (footprint) than the budget, burns CPU while nothing happens,
// or does not quit on SIGTERM (the way `kill`, the installer and logging out end it).
//
// On a fresh CI runner Accessibility is not allowed, so DockFlip shows its menu bar item and
// setup, as on a user's first launch. Build and run:
//   swiftc -O scripts/launch-check.swift -o build/launch-check
//   build/launch-check build/DockFlip.app
// It also takes a plain executable instead of an app bundle (the tests use /usr/bin/true).

import CoreGraphics
import Darwin
import Foundation

/// SCOPE.md: launch to usable < 0.5 s. CI runs on a shared virtual Mac that starts apps slower
/// than a real one, so the check allows it this many times the budget; the number it measured
/// is printed either way.
let scopeLaunchBudgetMs = 500.0
let ciLaunchAllowance = 6.0
/// SCOPE.md: memory (footprint) < 50 MB: what Activity Monitor shows as Memory. Resident
/// memory also counts the shared AppKit and SwiftUI pages every app maps, so it is only printed.
let memoryBudgetMB = 50.0
/// SCOPE.md: CPU at idle 0 %. A clock can't show exactly zero, so idle may use at most this
/// much of one core; a busy loop or a fast timer goes far over it.
let idleCPUBudgetPercent = 1.0

/// How long the app gets to put its first window on screen before the check gives up.
let windowTimeoutSeconds = 10.0
/// After the first window: time for the rest of launch to finish before memory is read.
let settleSeconds = 3.0
/// The idle stretch CPU time is measured over.
let idleSeconds = 5.0
/// How long the app gets to quit after SIGTERM.
let quitTimeoutSeconds = 5.0

var child: pid_t = 0

func fail(_ message: String) -> Never {
    print("::error::Launch check: \(message)")
    if child != 0 { kill(child, SIGKILL) }
    exit(1)
}

func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

func seconds(since start: UInt64) -> Double { Double(now() - start) / 1_000_000_000 }

/// The exit status once the child has quit, nil while it runs.
func exitStatus() -> Int32? {
    var status: Int32 = 0
    return waitpid(child, &status, WNOHANG) == child ? status : nil
}

/// Any window of the child on screen: the menu bar item or setup. Reading owners needs no
/// permission (only window titles need Screen Recording).
func hasWindowOnScreen() -> Bool {
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
        return false
    }
    return windows.contains { ($0[kCGWindowOwnerPID as String] as? Int) == Int(child) }
}

func usage() -> rusage_info_v4? {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(child, RUSAGE_INFO_V4, $0)
        }
    }
    return result == 0 ? info : nil
}

/// CPU time in nanoseconds. proc_pid_rusage counts in Mach time units, which are not
/// nanoseconds on Apple silicon.
func cpuNanoseconds(_ info: rusage_info_v4) -> Double {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    return Double(info.ri_user_time + info.ri_system_time) * Double(timebase.numer) / Double(timebase.denom)
}

func sleepWhileRunning(_ duration: Double) {
    let start = now()
    while seconds(since: start) < duration {
        if let status = exitStatus() { fail("the app quit on its own (wait status \(status))") }
        usleep(50_000)
    }
}

guard CommandLine.arguments.count == 2 else {
    print("usage: launch-check <App.app | executable>")
    exit(2)
}
let target = URL(fileURLWithPath: CommandLine.arguments[1])
var executable = target
if target.pathExtension == "app" {
    guard let url = Bundle(url: target)?.executableURL else { fail("\(target.path) is not an app bundle") }
    executable = url
}

// posix_spawn rather than Process, so this check reaps the child itself and sees it quit.
let path = executable.path
let argv: [UnsafeMutablePointer<CChar>?] = [strdup(path), nil]
let launchStart = now()
// The app gets this check's environment (HOME, PATH) unchanged. Built from ProcessInfo:
// `_NSGetEnviron` lives in <crt_externs.h>, which Swift's Darwin module does not bring in.
let envp: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
let spawned = posix_spawn(&child, path, nil, nil, argv, envp)
guard spawned == 0 else {
    child = 0
    fail("could not start \(path): \(String(cString: strerror(spawned)))")
}

while !hasWindowOnScreen() {
    if let status = exitStatus() { fail("the app quit on its own before showing a window (wait status \(status))") }
    if seconds(since: launchStart) > windowTimeoutSeconds {
        fail("no window on screen \(Int(windowTimeoutSeconds)) s after launch")
    }
    usleep(5_000)
}
let launchMs = seconds(since: launchStart) * 1000

sleepWhileRunning(settleSeconds)
guard let settled = usage() else { fail("could not read the app's resource use") }
let idleStart = now()
sleepWhileRunning(idleSeconds)
guard let idle = usage() else { fail("could not read the app's resource use") }
let idleCPUPercent = (cpuNanoseconds(idle) - cpuNanoseconds(settled)) / Double(now() - idleStart) * 100
let residentMB = Double(idle.ri_resident_size) / 1_048_576
let footprintMB = Double(idle.ri_phys_footprint) / 1_048_576

let launchBudgetMs = scopeLaunchBudgetMs * ciLaunchAllowance
let summary = String(
    format: "first window %.0f ms (CI budget %.0f), memory footprint %.1f MB (budget %.0f, resident %.1f), idle CPU %.2f %% (budget %.0f)",
    launchMs, launchBudgetMs, footprintMB, memoryBudgetMB, residentMB, idleCPUPercent, idleCPUBudgetPercent)
print("::notice::Launch check: \(summary)")

var problems: [String] = []
if launchMs > launchBudgetMs { problems.append(String(format: "first window after %.0f ms, over %.0f ms", launchMs, launchBudgetMs)) }
if footprintMB > memoryBudgetMB { problems.append(String(format: "memory footprint %.1f MB, over %.0f MB", footprintMB, memoryBudgetMB)) }
if idleCPUPercent > idleCPUBudgetPercent {
    problems.append(String(format: "idle CPU %.2f %%, over %.0f %%", idleCPUPercent, idleCPUBudgetPercent))
}

kill(child, SIGTERM)
let quitStart = now()
while exitStatus() == nil {
    if seconds(since: quitStart) > quitTimeoutSeconds {
        problems.append("did not quit \(Int(quitTimeoutSeconds)) s after SIGTERM")
        kill(child, SIGKILL)
        break
    }
    usleep(20_000)
}
child = 0

if !problems.isEmpty { fail(problems.joined(separator: "; ")) }
print("Launch check passed")

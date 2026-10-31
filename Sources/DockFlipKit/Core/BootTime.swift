import Darwin
import Foundation

/// The Mac's boot time, for stores in UserDefaults that keep window ids: macOS reuses
/// window ids after a restart, so ids saved in an earlier boot would name the wrong
/// windows. UsageTracker and PlacementMemory both save `now()` beside their ids and
/// trust them back only when `isSameBoot` says so.
enum BootTime {
    /// When the Mac booted, in seconds since 1970; 0 when sysctl can't tell.
    static func now() -> TimeInterval {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0 else { return 0 }
        return TimeInterval(time.tv_sec)
    }

    /// Whether data saved at boot time `saved` belongs to this boot (`now`). The boot time
    /// read back can drift a little, hence the minute's slack. 0 on either side means never
    /// saved or unreadable: not this boot, since trusting it could date the wrong windows.
    static func isSameBoot(saved: TimeInterval, now: TimeInterval = BootTime.now()) -> Bool {
        saved > 0 && now > 0 && abs(saved - now) < 60
    }
}

import AppKit
import ServiceManagement
import Sparkle

/// Sparkle auto-updates. Only armed when running from an assembled .app
/// bundle — the bare SwiftPM executable (dev runs, --selftest, CI) has no
/// Info.plist feed/key and Sparkle would refuse to start.
@MainActor
enum UpdaterService {
    static let isAvailable = Bundle.main.bundleURL.pathExtension == "app"

    static let controller: SPUStandardUpdaterController? = {
        guard isAvailable else { return nil }
        return SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    static func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

/// Launch-at-login via SMAppService — also bundle-only (the bare executable
/// has no main-app service identity to register).
@MainActor
enum AutostartService {
    static var isAvailable: Bool { UpdaterService.isAvailable }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}

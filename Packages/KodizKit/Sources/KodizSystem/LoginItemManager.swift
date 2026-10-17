import Foundation
import ServiceManagement

public enum LoginItemManager {
    public static var isEnabled: Bool {
        return SMAppService.mainApp.status == .enabled
    }

    public static var status: SMAppService.Status {
        return SMAppService.mainApp.status
    }

    public static func register() throws {
        try SMAppService.mainApp.register()
    }

    public static func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    public static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

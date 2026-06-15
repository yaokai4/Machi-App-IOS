//
//  kaiziApp.swift
//  kaizi
//
//  Created by 姚凯 on 2026/5/21.
//

import SwiftData
import SwiftUI

/// Carries the UIKit callbacks SwiftUI has no home for — the APNs device
/// token handoff. Registration failures are silent by design (simulators
/// and dev-signed builds fail routinely; local banners still work).
final class MachiAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushTokenService.systemDidIssue(token: deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
    }
}

@main
struct kaiziApp: App {
    @UIApplicationDelegateAdaptor(MachiAppDelegate.self) private var appDelegate
    private let modelContainer = KaiXDatabaseContainer.shared

    init() {
        // Must be installed before the first banner is shown or tapped,
        // so foreground presentation + tap routing work from cold start.
        SystemNotificationService.shared.activate()
        // Subscribe to MetricKit so crash / hang diagnostics from the
        // previous run are captured on this launch.
        DiagnosticsService.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}

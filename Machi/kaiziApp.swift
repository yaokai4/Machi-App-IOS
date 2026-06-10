//
//  kaiziApp.swift
//  kaizi
//
//  Created by 姚凯 on 2026/5/21.
//

import SwiftData
import SwiftUI

@main
struct kaiziApp: App {
    private let modelContainer = KaiXDatabaseContainer.shared

    init() {
        // Must be installed before the first banner is shown or tapped,
        // so foreground presentation + tap routing work from cold start.
        SystemNotificationService.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}

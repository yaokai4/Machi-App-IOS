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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}

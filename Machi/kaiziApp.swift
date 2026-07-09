//
//  kaiziApp.swift
//  kaizi
//
//  Created by 姚凯 on 2026/5/21.
//

import SwiftData
import SwiftUI
import UIKit

/// 后台快照隐私遮罩:App 退到后台时 iOS 会截当前界面作为多任务切换器预览,
/// 打开中的私信正文会留在快照里被旁观者看到。resign active 时在最顶层挂一个
/// 不透明遮罩 UIWindow(比 SwiftUI overlay 高一层——它能盖住 sheet /
/// fullScreenCover,根视图 overlay 盖不住),回到 active 再整窗移除。
/// 代价是权限弹窗/控制中心期间也会短暂遮罩——与主流私密类 App 行为一致。
@MainActor
final class PrivacyShieldService {
    static let shared = PrivacyShieldService()
    private var shieldWindow: UIWindow?

    func activate() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in PrivacyShieldService.shared.show() }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in PrivacyShieldService.shared.hide() }
        }
    }

    private func show() {
        guard shieldWindow == nil,
              let scene = UIApplication.shared.connectedScenes
                  .compactMap({ $0 as? UIWindowScene })
                  .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
        else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.rootViewController = UIHostingController(rootView: PrivacyShieldView())
        window.isHidden = false
        shieldWindow = window
    }

    private func hide() {
        shieldWindow?.isHidden = true
        shieldWindow = nil
    }
}

/// The opaque cover the system snapshots instead of live content: brand mark
/// on the system background, both appearances supported.
private struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .kxScaledFont(40, weight: .semibold)
                    .foregroundStyle(KXColor.accent)
                Text("Machi")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .ignoresSafeArea()
    }
}

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
        // 私密内容(私信正文等)不得留在多任务切换器快照里。
        PrivacyShieldService.shared.activate()
        // Sweep stale staged-media upload copies (age > 48h or dir > 500 MB) once
        // per launch so a long-running app can't accumulate orphaned scratch.
        Task.detached(priority: .background) {
            await UploadService.shared.trimStagedMedia()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}

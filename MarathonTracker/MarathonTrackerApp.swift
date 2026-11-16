import SwiftUI
import UserNotifications

enum AppTab: Hashable {
    case daily
    case run
    case review
}

@main
struct MarathonTrackerApp: App {
    @StateObject private var store = TrackerStore()
    @StateObject private var router = NotificationRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView(selection: $router.selectedTab) {
                DailyView()
                    .tabItem { Label("今日", systemImage: "sun.max") }
                    .tag(AppTab.daily)
                ContentView()
                    .tabItem { Label("ラン", systemImage: "figure.run") }
                    .tag(AppTab.run)
                WeeklyReviewView()
                    .tabItem { Label("振り返り", systemImage: "calendar") }
                    .tag(AppTab.review)
            }
            .environmentObject(store)
            .onAppear {
                UNUserNotificationCenter.current().delegate = router
                NotificationManager.requestAuthorization()
                NotificationManager.reschedule(store: store)
                Task { await HealthKitManager.shared.syncAll(into: store) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    NotificationManager.reschedule(store: store)
                    Task { await HealthKitManager.shared.syncAll(into: store) }
                }
            }
        }
    }
}

import SwiftUI

@main
struct MarathonTrackerApp: App {
    @StateObject private var store = TrackerStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    NotificationManager.requestAuthorization()
                    NotificationManager.reschedule(store: store)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        NotificationManager.reschedule(store: store)
                        Task { await HealthKitManager.shared.syncWorkouts(into: store) }
                    }
                }
        }
    }
}

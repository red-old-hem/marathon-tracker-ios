import Foundation
import UserNotifications

/// 火・木・土の朝7時にメニュー通知、毎日20時に未チェックなら確認通知(どちらもレース日まで)。
/// 平日19時には、30秒メモが未記入なら仕事メモの通知(レース後も続ける)。
/// アプリ起動時とチェックイン時に直近14日分を組み直す。
@MainActor
enum NotificationManager {
    static let runWeekdays: Set<Int> = [3, 5, 7] // Calendar.weekday: 火=3, 木=5, 土=7
    static let noteWeekdays: Set<Int> = [2, 3, 4, 5, 6] // 月〜金
    static let noteHour = 19
    static let notePrefix = "note-"

    /// 30秒メモの通知を予約する日。平日で、その日のメモがまだない日
    static func noteReminderDays(from today: Date, store: TrackerStore) -> [Date] {
        let cal = Plan.calendar
        let start = cal.startOfDay(for: today)
        return (0..<14).compactMap { cal.date(byAdding: .day, value: $0, to: start) }.filter {
            noteWeekdays.contains(cal.component(.weekday, from: $0)) && store.workNote(on: $0) == nil
        }
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func reschedule(store: TrackerStore) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let cal = Plan.calendar
        let today = cal.startOfDay(for: Date())

        for day in noteReminderDays(from: today, store: store) {
            schedule(center: center, id: "\(notePrefix)\(store.key(for: day))", day: day, hour: noteHour,
                     title: "今日の30秒メモ", body: "少し面白かった作業と、消耗した作業を一語ずつ残そう")
        }

        // 岡山のレースまで。レース後は次の目標の開催日まで(目標がなければラン通知はなし)
        let lastDay = Plan.isAfterRace(today) ? store.nextGoal.map { cal.startOfDay(for: $0.date) } : Plan.race
        guard let lastDay, today <= lastDay else { return }

        for offset in 0..<14 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today), day <= lastDay else { continue }
            guard store.log(on: day) == nil else { continue }
            let weekday = cal.component(.weekday, from: day)

            if runWeekdays.contains(weekday) {
                if let warning = store.painWarning() {
                    schedule(center: center, id: "morning-\(store.key(for: day))", day: day, hour: 7,
                             title: "今日は休養推奨", body: "\(warning.part.label)の痛みが続いています。無理せず休むか短いジョグに")
                } else {
                    let nextMenu = store.nextMenu(on: day) ?? "ラン"
                    schedule(center: center, id: "morning-\(store.key(for: day))", day: day, hour: 7,
                             title: "今日は走る日", body: "メニュー: \(nextMenu)。玄関のウェアを着るだけでOK")
                }
            }

            let eveningBody = runWeekdays.contains(weekday)
                ? "まだ間に合う。5分だけでもOK、ゼロの日を作らないのが勝ち"
                : "今日のチェックインは済んだ?走ったなら記録を。休養日ならそのままでOK"
            schedule(center: center, id: "evening-\(store.key(for: day))", day: day, hour: 20,
                     title: "今日の確認", body: eveningBody)
        }
    }

    private static func schedule(center: UNUserNotificationCenter, id: String, day: Date, hour: Int, title: String, body: String) {
        var comps = Plan.calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = hour
        guard let fireDate = Plan.calendar.date(from: comps), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

/// 通知のタップで開くタブを切り替える
@MainActor
final class NotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    @Published var selectedTab: AppTab = .daily

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        await MainActor.run {
            selectedTab = id.hasPrefix(NotificationManager.notePrefix) ? .daily : .run
        }
    }
}

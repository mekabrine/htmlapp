import AppIntents
import ActivityKit

@available(iOS 17.0, *)
struct HTMLAppEndLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End HTMLApp activity"
    static var openAppWhenRun = false
    @Parameter(title: "App") var appID: String
    @Parameter(title: "Activity") var activityID: String
    init() {}
    init(appID: String, activityID: String) { self.appID = appID; self.activityID = activityID }
    func perform() async throws -> some IntentResult {
        if let activity = Activity<HTMLAppLiveActivityAttributes>.activities.first(where: {
            $0.attributes.appID == appID && $0.attributes.activityID == activityID
        }) {
            await activity.end(ActivityContent(state: activity.content.state, staleDate: nil), dismissalPolicy: .immediate)
        }
        return .result()
    }
}

struct HTMLAppLiveActivityAction: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var kind: String
}

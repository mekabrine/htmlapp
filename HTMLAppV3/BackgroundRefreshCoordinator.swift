import Foundation
import BackgroundTasks
import WidgetKit

final class HTMLAppBackgroundCoordinator {
    static let shared = HTMLAppBackgroundCoordinator()
    static let taskIdentifier = "com.mekabrine.htmlapp.refresh"

    private init() {}

    @discardableResult
    func register() -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(refresh)
        }
    }

    func schedule() {
        let jobs = HTMLAppBackgroundJobStore.all().filter { $0.enabled }
        let widgetRefreshes = HTMLAppWidgetStore.all().filter { $0.refresh != nil }
        guard !jobs.isEmpty || !widgetRefreshes.isEmpty else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
            return
        }

        let intervals = jobs.map(\.intervalMinutes) + widgetRefreshes.compactMap { $0.refresh?.intervalMinutes }
        let minutes = max(15, intervals.min() ?? 30)
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(TimeInterval(minutes * 60))

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Background refresh is opportunistic and may be unavailable under
            // device policy, Low Power Mode, or the user's Background App Refresh setting.
        }
    }

    func runNow(appID: String? = nil, jobID: String? = nil) async -> [HTMLAppBackgroundFetchJob] {
        await runJobs(force: true, appID: appID, jobID: jobID)
    }

    /// APNs background wakeups only refresh *due* approved jobs; they cannot
    /// force execution of unrelated saved apps or bypass their network grants.
    func runDueJobs() async -> [HTMLAppBackgroundFetchJob] {
        await runJobs(force: false, appID: nil, jobID: nil)
    }

    private func handle(_ task: BGAppRefreshTask) {
        schedule()

        let worker = Task {
            let results = await runJobs(force: false, appID: nil, jobID: nil)
            if Task.isCancelled {
                task.setTaskCompleted(success: false)
            } else {
                task.setTaskCompleted(success: !results.contains(where: { $0.lastError != nil }))
            }
        }

        task.expirationHandler = {
            worker.cancel()
        }
    }

    private func runJobs(force: Bool, appID: String?, jobID: String?) async -> [HTMLAppBackgroundFetchJob] {
        let now = Date()
        var results: [HTMLAppBackgroundFetchJob] = []

        for original in HTMLAppBackgroundJobStore.all() {
            if Task.isCancelled { break }
            guard original.enabled else { continue }
            if let appID, original.appID != appID { continue }
            if let jobID, original.jobID != jobID { continue }

            let due = original.lastRunAt.map {
                now.timeIntervalSince($0) >= TimeInterval(max(15, original.intervalMinutes) * 60)
            } ?? true
            guard force || due else { continue }

            var job = original
            do {
                let stored = try await fetch(job)
                HTMLAppPortableDataStore.set(appID: job.appID, key: job.storageKey, value: stored)
                job.lastRunAt = Date()
                job.lastError = nil

                if let widgetID = job.widgetID,
                   let widget = HTMLAppWidgetStore.definitions(appID: job.appID).first(where: { $0.widgetID == widgetID }) {
                    let refreshed = await HTMLAppWidgetNetwork.refreshed(widget)
                    try HTMLAppWidgetStore.repository().refresh(refreshed, original: widget)
                }
            } catch {
                job.lastRunAt = Date()
                job.lastError = error.localizedDescription
            }

            HTMLAppBackgroundJobStore.updateRuntimeState(
                id: job.id,
                lastRunAt: job.lastRunAt,
                lastError: job.lastError
            )
            results.append(job)
        }

        // Widget providers show the committed cached snapshot immediately;
        // scheduled host refresh keeps public HTTPS widget content updated
        // without blocking WidgetKit's timeline callback.
        var refreshedWidgets = false
        for widget in HTMLAppWidgetStore.all() where widget.refresh != nil {
            if Task.isCancelled { break }
            let minutes = max(15, widget.refresh?.intervalMinutes ?? 30)
            let due = widget.lastRefreshAt.map { now.timeIntervalSince($0) >= Double(minutes * 60) } ?? true
            guard force || due else { continue }
            let refreshed = await HTMLAppWidgetNetwork.refreshed(widget)
            do {
                try HTMLAppWidgetStore.repository().refresh(refreshed, original: widget)
                refreshedWidgets = true
            } catch {
                NSLog("HTMLApp widget background update failed: %@", error.localizedDescription)
            }
        }
        if !results.isEmpty || refreshedWidgets {
            await MainActor.run {
                HTMLAppWidgetReloadCoordinator.request()
            }
        }
        schedule()
        return results
    }

    private func fetch(_ job: HTMLAppBackgroundFetchJob) async throws -> String {
        guard let host = HTMLAppNetworkBridge.validatedHost(["url": job.url]) else {
            throw URLError(.unsupportedURL)
        }
        // The same per-app permission and domain consent applies to scheduled
        // work as to foreground network.request. Imported/stale jobs which
        // lack these grants cannot secretly contact a hostname.
        let approved = await MainActor.run {
            HTMLPermissionStore.choice(for: .network, appID: job.appID) == .allow &&
            HTMLAppNetworkDomainConsent.approved(for: job.appID).contains(host)
        }
        guard approved else { throw URLError(.userAuthenticationRequired) }

        // Reuse bounded, no-cookie, no-redirect, public-DNS/remote-IP verified
        // HTTPS transport instead of unrestricted URLSession.shared.
        let response = try await HTMLAppNetworkBridge.perform([
            "url": job.url, "method": "GET"
        ])
        guard response["ok"] as? Bool == true,
              let raw = response["body"] as? String,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            throw URLError(.badServerResponse)
        }
        let selected = job.jsonPath.flatMap { path in
            HTMLAppJSONPath.value(at: path, in: json)
        } ?? json
        guard let result = HTMLAppJSONPath.jsonString(selected) else {
            throw CocoaError(.propertyListWriteInvalid)
        }
        return result
    }
}

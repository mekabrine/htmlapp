# Offline reminders in HTMLApp

## Findings

Apple's UserNotifications framework schedules local requests with the operating system. iOS handles delivery while the app is in the background or is not running. Once successfully scheduled, a time-based local reminder does not require internet, an APNs key/certificate, a push server, or JavaScript continuing to execute. User permission and system notification settings still govern presentation. Focus and notification settings can affect when/how alerts appear; this is not a guaranteed alarm service.

This covers reminders known ahead of time. A killed app cannot discover new remote events or execute arbitrary HTML/JavaScript logic at the deadline. Such logic must be evaluated before scheduling, or when the user next opens the app. Remote events still need remote push infrastructure.

Sources:
- https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app
- https://developer.apple.com/documentation/usernotifications/untimeintervalnotificationtrigger
- https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger
- https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/SchedulingandHandlingLocalNotifications.html

## Existing implementation

`HTMLAppNative.notifications.schedule({id,title,body,at?,afterSeconds?,silent?,sound?})` already requests saved-app and system consent, constructs a one-time UNTimeIntervalNotificationTrigger, and reports success after UNUserNotificationCenter.add completes. Identifiers use `native.<appID>.` so projects stay separate. `notifications.cancel({id})` cancels a particular reminder; cancellation without an ID scopes to the current project. `notifications.installSound` supports imported notification sounds. This works on the current minimum iOS16 target without Apple Intelligence.

Example: from an explicit reminder button, call `await HTMLAppNative.notifications.schedule({id:'tea',title:'Tea is ready',body:'Your timer finished.',afterSeconds:180})`. Schedule when starting the timer, not inside setTimeout at its end. Cancel when the timer is cancelled. Show success only after the promise resolves; show permission and scheduling errors clearly.

## Proposed next integration

1. Keep the existing schedule/cancel contract backward compatible. Validate finite future dates, bounded text/IDs and repeat parameters; return the effective fire time and native identifier. Never silently turn an invalid date into an immediate reminder.
2. Add calendar recurrence (daily/weekly at a chosen local time) using UNCalendarNotificationTrigger, with explicit time-zone/daylight-saving behavior. Use native repeating triggers rather than scheduling JavaScript callbacks or indefinitely filling a queue.
3. Add owner-scoped pending/delivered lists and a permission/status API. Persist project metadata for each reminder and reconcile with the actual OS pending requests at launch. Enforce a conservative shared pending budget across projects and report capacity errors instead of claiming unlimited reminders.
4. Add a Reminders section in Settings showing project, content, next trigger, recurrence and permission state, with individual/project cancellation. On project deletion remove only that project's requests and records.
5. Store appID and a validated route in notification userInfo. A notification tap should queue its launch context until onboarding/presentation is ready, then open the owning saved HTML app. Never run arbitrary HTML in a background response handler.
6. Update Forge's existing API catalog and authoring examples to schedule reminders immediately while foregrounded, handle cancellation/denial, and explain offline behavior. Preserve the restored 1.9.11 generation and QA policy.
7. Test manually on iOS16.2 and iPadOS26.4.2: airplane mode, screen locked, app force-quit after scheduling, cancelled/replaced reminders, permission denial, two project IDs with identical reminder IDs, cold-start notification taps, and calendar/time-zone changes. No background JavaScript or APNs setup should be part of these tests.

The reminder extensions above are a plan, not features shipped in this repair.

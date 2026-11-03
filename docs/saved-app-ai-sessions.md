# Saved-app AI sessions

In addition to the existing single-shot `ai.complete`, saved HTML apps can now create bounded, in-memory AI sessions.

```js
const session = HTMLAppNative.ai.createSession({
  system: "You are a concise personal assistant.",
  tools: ["calendar.events", "reminders.list", "db.searchFullText", "device.battery"]
});
const answer = await session.ask("What's next on my calendar?");
console.log(answer.text);
session.clear();
```

Only tools explicitly listed in `tools` can be requested. Supported tools are `calendar.events`, `calendar.createEvent`, `reminders.list`, `reminders.create`, `health.today`, `db.get`, `db.query`, `db.search`, `db.searchFullText`, `location.current`, and `device.battery`. The SDK intentionally excludes unrestricted bridge calls.

Each sensitive tool request displays a **native per-call confirmation** before running the operation or sending any returned data to the configured cloud AI provider. Existing host and OS permissions apply as well; approvals cannot bypass them. Results are truncated to 2,000 characters and no more than three tools are used per question. A short bounded conversation remains only inside that saved app's foreground WebView. Closing the WebView loses it. The helper cannot run after iOS suspends the app.

Provider setup, AI access policy, and the existing per-minute quota remain in force. Use an `AbortSignal` with `session.ask(prompt, {signal})` to cancel a pending response; the bridge cancels the underlying in-flight task. The helper is JSON-protocol-based rather than provider-native tool APIs, so incorrect model JSON can produce a plain answer or a bounded failure. It is **not** unrestricted agent execution and does not guarantee a tool decision.

Do not enable sensitive tools without making clear to the user that their data could reach the configured AI provider after confirmation.

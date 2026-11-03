# Native sheet lists and pull-to-refresh

```js
const off = HTMLAppNative.events.on('ui-list-refresh', async ({sessionID}) => {
  const data = await HTMLAppNative.db.query('notes', {limit: 25});
  await HTMLAppNative.ui.listUpdate(
    data.items.map(item => ({id:item.id,title:item.document.title})),
    sessionID
  );
});
try {
  const choice = await HTMLAppNative.ui.list({
    title: 'Choose a note',
    items: [{id:'first',title:'Morning journal',detail:'Updated today'}],
    allowsRefresh: true
  });
  if (!choice.cancelled) console.log(choice.id);
} finally { off(); }
```

`ui.list` presents a real, accessible UIKit sheet and returns a selection or cancel result. The list allows at most 200 items with unique IDs and bounded title/detail strings. It cannot open arbitrary native view controllers or replace your application's route system. A pull gesture dispatches `htmlapp:ui-list-refresh` with a session ID; the visible saved app must perform the work in the foreground and call `ui.listUpdate` to end the spinner. Use `ui.listDismiss()` if needed. The host closes its list if the saved app exits.

The caller should feature-detect the APIs on older HTMLApp versions; no background execution, arbitrary native navigation stack or App Intent registration is implied.

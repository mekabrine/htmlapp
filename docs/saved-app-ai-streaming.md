# Live AI token streaming for saved HTML apps

```js
const controller = new AbortController();
let output = '';
const result = await HTMLAppNative.ai.stream({
  prompt: 'Explain how the app works.',
  system: 'Answer clearly.',
  maxTokens: 600,
  signal: controller.signal,
  onToken(token, detail) {
    output += token;
    document.querySelector('#response').textContent = output;
  }
});
console.log(result.text); // Complete response
// controller.abort() cancels a pending request.
```

The bridge uses the configured AI provider's actual streamed tokens (not fake chunks). It only executes in the foreground when saved-app AI is enabled and permitted; the existing per-app ten-requests-per-minute budget applies. Events are dispatched as `htmlapp:ai-stream` with `requestID`, `delta`, and `done`, and callbacks are scoped to the matching request. The JS SDK removes listeners on completion, error or cancellation.

Swift limits total returned stream text to 128 KB. Unsupported providers or cancelled streams return an error and never imply a successful completion. This is not a guaranteed background task.

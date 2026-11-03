# On-device structured AI and optional cloud fallback

On supported iOS 26 devices with Apple's Foundation Models enabled, apps can use structured output:

```js
const answer = await HTMLAppNative.ai.localComplete({
  prompt: "Summarize this text in one sentence.",
  format: "structured"
});
console.log(answer.answer, answer.summary, answer.confident);
```

The output is generated with Apple's `@Generable` guided-generation API and has three typed fields: `answer: string`, `summary: string` and `confident: boolean`. It does not promise arbitrary JSON schema support, which remains separate from the bounded `format:"json"` mode. The prompt is limited to 4 KB, system instruction 1.2 KB and four local requests per saved app per minute. This does not extend the model's device memory/context limits.

To *offer* a cloud fallback only when local inference fails:

```js
const answer = await HTMLAppNative.ai.localComplete({
  prompt: "Give me a concise answer.",
  fallback: "cloud",
  format: "structured"
});
if (answer.provider === "cloud") console.log("Cloud fallback used.");
```

HTMLApp displays a native **Switch to Cloud AI?** approval prompt before forwarding anything. Declining sends no prompt to the provider. Cloud fallback also requires a configured cloud provider and is counted against cloud AI limits. The request itself cannot bypass the saved app's AI permission. Cloud providers may not satisfy the structured format; the bridge rejects invalid fields rather than claiming valid results. Background execution is not provided.

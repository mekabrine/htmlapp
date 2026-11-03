# Cost and typed capability planning

Forge now bundles the same generated `htmlapp-native-api.d.ts` file published in `docs/` as an app resource and feeds its native method signatures to the builder and edit agent. The schema remains authoritative: this does not circumvent runtime permissions or guarantee hardware access.

Identical planner requests can reuse the same in-memory plan for up to 12 minutes, keyed by provider, model, request and whether the input came from dictation. Failed planner calls are not cached and the app does not persist the plan cache or user prompts to disk.

AI Settings > Advanced options > AI Work Cost Estimate offers a user-supplied *output* price per one million tokens. When nonzero, the Forge work timeline displays an estimate by stage, using the approximate source-text size divided by four bytes per token. The estimate excludes provider input/reasoning tokens, cached tokens, images, role-dependent prices and any actual provider billing: **it is not a charge, an invoice or provider usage accounting**. Set the rate to zero to hide estimated costs. The stage timings themselves are observed elapsed times.

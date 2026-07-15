## Highlights

- **Grok Build is now a first-class client.** TokenBar reads local Grok sessions throughout its usage reports and shows weekly Grok quota when OAuth credentials are available. [#37](https://github.com/Nanako0129/TokenBar/pull/37) — thanks @savourylie

## Changes

- **Named Hermes profiles are discovered automatically,** including profile-only homes without a default database. [#49](https://github.com/Nanako0129/TokenBar/pull/49)
- **Deep Claude workflow transcripts now contribute to local usage reports,** while orchestration journals remain excluded and cached parent attribution stays fresh. [#43](https://github.com/Nanako0129/TokenBar/pull/43)

## Fixes

- **Provider-reported costs remain authoritative** for GJC and OpenCode instead of being overwritten by pricing estimates, including across duplicate local sources. [#39](https://github.com/Nanako0129/TokenBar/pull/39)
- **Pi sessions with leading title metadata are no longer skipped,** and Pi subagent usage is attributed to the correct agent. [#42](https://github.com/Nanako0129/TokenBar/pull/42)
- **Nested Copilot usage is attributed to the correct root agent,** including traces with attribute-less intermediate spans or reused span IDs. [#44](https://github.com/Nanako0129/TokenBar/pull/44)
- **Jcode correction records no longer consume the next real turn,** preventing turn-count underreporting after snapshot corrections. [#41](https://github.com/Nanako0129/TokenBar/pull/41)
- **Metadata-only updates now refresh usage reliably** for Roo Code, Kilo Code, Cline, Droid, Kimi, and Kiro instead of replaying stale models, pricing, tokens, or durations. [#50](https://github.com/Nanako0129/TokenBar/pull/50) [#51](https://github.com/Nanako0129/TokenBar/pull/51)
- **Token totals saturate safely on corrupt or extreme input** instead of overflowing in reports or the live-rate path. [#38](https://github.com/Nanako0129/TokenBar/pull/38)
- **Codex model-performance timing no longer counts overlapping intervals** when a turn emits multiple accepted token snapshots. [#52](https://github.com/Nanako0129/TokenBar/pull/52)

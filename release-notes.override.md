## Highlights

- **Monthly lens.** Browse active months newest-first with message, token, and cost totals plus per-model drill-down. Optional lenses can be hidden from Settings, and message-only months remain visible. [#54](https://github.com/Nanako0129/TokenBar/pull/54) — thanks @yiskang

## Changes

- **Codex Weekly historical pace now starts from a clean, account-scoped history.** Expected usage, run-out timing, and risk now come from one consistent projection. Learning restarts after this update, and Linear pace remains active until enough complete weeks are collected. [#55](https://github.com/Nanako0129/TokenBar/pull/55)

## Fixes

- **Quota projections remain readable in compact cards.** When pace, ETA, and risk no longer fit on one line, timing and risk move to a second, right-aligned line without changing the underlying values. [#56](https://github.com/Nanako0129/TokenBar/pull/56)

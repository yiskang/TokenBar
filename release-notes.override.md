## Performance

TokenBar was holding a CPU core busy in the background. Its log-parsing engine ran one worker thread per CPU core, and each idle thread spin-waited before parking, so on a multi-core Mac the thread pool alone burned close to a full core. The popover also kept its polling loops running after it closed.

This release caps the parser to two worker threads, pauses the popover's polling while it is hidden, and removes a settings-change feedback loop that could re-trigger full log re-reads. Sustained CPU usage is down by roughly 60%. [#16](https://github.com/Nanako0129/TokenBar/pull/16)

The figures below are the %CPU shown in Activity Monitor (where 100% is one core), measured on a 10-core Mac:

| State | Before | After |
| --- | --- | --- |
| Idle, popover closed | 15-25% | ~8% |
| Idle, popover open | 40-65% | ~20% |

The idle saving grows with core count, since the old thread pool scaled with it.

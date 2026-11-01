# Console, logs and crash reports

`katsa.log` is the single sink for diagnostics. It has three levels (`log`, `warn`,
`error`), a bounded in-memory history (2000 entries, `katsa.log.setLimit`), listeners and
an optional file sink.

```lua
katsa.log.warn('Texture missing', 'Resources')
katsa.log.error('Unrecoverable', 'Physics')
local errors = katsa.log.entries('error')     -- at or above a level
local hits = katsa.log.entries(nil, 'Texture') -- plain-text filter
local stop = katsa.log.subscribe(function(entry) end)
```

Warnings and errors go to stderr, `log` to stdout, so a launcher can pipe them. The
`print` function is captured (level `log`, source `print`) while a normal run is active.
Automated test and smoke runs do not capture `print` or write log files.

## Files (save directory)

| File | Content |
| --- | --- |
| `logs/latest.log` | Current run, one line per entry: `UTC [level] message` |
| `logs/previous.log` | The run before |
| `logs/console-<UTC>.json` / `.csv` | Manual exports (`source/engine/debug/logExport.lua`) |
| `crashes/crash-01.log` … `crash-10.log` | Lua error reports, newest first, with the last 50 log lines |
| `last-error.log` | Copy of the newest crash report |

JSON exports contain `schema`, `app_version` and `entries` (`id`, `utc`, `time`, `level`,
`source`, `message`). CSV uses the same columns with RFC 4180 quoting.

The runtime journal (`manager.journal`) mirrors every recorded error into `katsa.log` as
level `error`. A native process fault cannot be logged by Lua.

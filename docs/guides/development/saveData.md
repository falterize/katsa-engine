# Save data

The save identity is `katsa-engine`. On Windows the default folder is
`%APPDATA%/Katsa/katsa-engine`. Use `katsa.filesystem.getSaveDirectory()` for the
actual location on other platforms. Stats CSV files live in `stats-logs/`;
verified native libraries live in content-addressed `native-cache/` directories.
Project source, assets and vendor files stay inside the project or archive.

The identity is the `identity` string in the project's `project.lua`. Saves kept under an older identity are not migrated.

## Example

```lua
print(katsa.filesystem.getSaveDirectory())          -- where the files live on this machine

local data = scene.data:scope('shooter')
data:write('best.txt', '120')                       -- saves/shooter/best.txt
print(data:read('best.txt'))                        -- '120', also in the next run
```
## Game progress and preferences

Use the [persistence API](persistence.md) for versioned progress slots and settings.
Identity migration and gameplay schema migration are separate operations.
A [generated game](newGame.md) receives its own identity and does not import
the example collection's saves automatically.

<!-- book:nav -->
---
**Katsa book** · chapter 11, Reference · page 2 of 10

[← Scene data: folders and files](persistence.md) · [Contents](../../book/README.md) · [Background execution and time scale →](backgroundExecution.md)
<!-- /book:nav -->

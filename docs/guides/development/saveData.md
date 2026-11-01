# Save data

The save identity is `katsa-engine`. On Windows the default folder is
`%APPDATA%/Katsa/katsa-engine`. Use `katsa.filesystem.getSaveDirectory()` for the
actual location on other platforms. Stats CSV files live in `stats-logs/`;
verified native libraries live in content-addressed `native-cache/` directories.
Project source, assets and vendor files stay inside the project or archive.

`source/engine/core/saveData.lua` performs a one-time migration from the previous
`katsa-sbox-v73` identity before scene services create caches. It copies only
entries belonging to the legacy save mount, excludes project assets and symlinks,
and preserves existing destination files. The previous folder remains available
to older releases. Successful completion writes `.legacy-save-migrated` in the
new folder; later launches do not copy the old folder again.

A failed read/write restores the current identity and leaves migration retryable.
The old files remain untouched. Startup prints a migration failure to the console;
check folder permissions if it appears. New logs and caches always use the new
identity. Migration never uploads or deletes user data.

## Game progress and preferences

Use the [persistence API](persistence.md) for versioned progress slots and settings.
Identity migration and gameplay schema migration are separate operations.
A [generated game](newGame.md) receives its own identity and does not import
the example collection's saves automatically.

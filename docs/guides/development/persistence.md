# Scene data: folders and files

Every scene has `scene.data`. Use `scope` to select a folder, then `read` and
`write` for progress, preferences, text or binary files. Data lives outside the
replaceable game source/archive and can be read by another scene or later run.
No settings-specific object is required.

## Folders and nested scopes

```lua
local shooter = scene.data:scope('shooter')
local extra = shooter:scope('extra')
local sameExtra = scene.data:scope('shooter/extra')

assert(shooter:write('settings.txt', 'volume=0.8\n'))
assert(extra:write('fun.txt', 'Hello!'))
assert(sameExtra:read('fun.txt') == 'Hello!')
```

```text
<application save directory>/
  saves/
    shooter/
      settings.txt
      extra/
        fun.txt
```

At `scene.data`, `scope('shooter')` selects a top-level category. Further scopes
are relative: `shooter:scope('extra')` is `shooter/extra`, not a separate `extra`.
Slash-separated paths and chained calls are equivalent. Scopes do not create
folders until a write or explicit `createDirectory` call. Other scenes use the
same scope path to access the same committed data.

The unscoped `scene.data:write(...)` uses the existing `shared` category. Outside
a scene, `Data.new('shooter/extra')` from `source.engine.persistence.data` accesses
that same category. `Data.new()` behaves like the scene's top-level selector.

Children inherit filesystem and byte limits. Defaults, versions and migrations
belong to their own data and are not inherited from an unrelated parent folder.

## One read/write API

```lua
local data = scene.data:scope('shooter')
local preferences, info = data:read('settings.json', {
    defaults = { rotationEnabled = true, volume = 0.8 },
})
assert(preferences, info)

preferences.rotationEnabled = false
local ok, failure = data:write('settings.json', preferences)
assert(ok, failure)

local progress, metadata = data:read('progress.json', {
    defaults = { score = 0 },
})
assert(progress, metadata)
progress.score = progress.score + 10
assert(data:write('progress.json', progress))
```

The first argument is the filename, including its extension. Nested paths work
there too: `data:write('profiles/player-1/progress.json', progress)`.

| Filename / override | Value written | Value returned by read |
| --- | --- | --- |
| `progress.json` | JSON-compatible Lua table | A new Lua table, plus metadata |
| `settings.txt`, `log.csv`, `world.bin`, other extensions | String or LOVE Data object | Original bytes as a Lua string, plus metadata |
| `{ format = 'json' }` | Lua table, regardless of extension | Verified Lua table; use the same override on read |
| `{ format = 'text' }` or `{ format = 'binary' }` | Original bytes, regardless of extension | Original bytes |

Extensions make the default reader predictable. Tables normally use `.json`;
trying to write a table to `.txt` without an override returns an explanatory
error. Text and binary handling preserve bytes without encoding conversion.
For example, external JSON text can be kept verbatim:

```lua
assert(data:write('external.json', '{"volume":0.8}', { format = 'text' }))
local original = assert(data:read('external.json', { format = 'text' }))

-- A custom extension can hold structured data when both calls specify its format.
assert(data:write('settings.txt', preferences, { format = 'json' }))
local restored = assert(data:read('settings.txt', { format = 'json' }))
```

Settings are ordinary data. Loading a preferences table does not apply audio,
window or input changes automatically; the game's code decides when to apply it.
Edits stay in memory until `write`. Save at checkpoints or after a user action,
not every frame. Both reads and writes are synchronous.

## Defaults, errors and versions

`read` returns `value, metadata`, or `nil, error`. A missing JSON document returns
independent defaults (an empty table if none were supplied) with `status = 'new'`.
A missing raw file returns an error. Existing damaged JSON is not treated as a
new save. Metadata for tables includes `status`, `version`, `generation` and an
optional `migrated` flag. Handle errors before modifying the value.

Defaults and schemas can be defined on a scope or passed to a JSON read/write:

```lua
local options = {
    version = 2,
    defaults = { score = 0 },
    migrations = {
        [1] = function(value)
            value.score = value.points or 0
            value.points = nil
            return value
        end,
    },
}
local progress, metadata = data:read('progress.json', options)
assert(progress, metadata)
assert(data:write('progress.json', progress, options))
```

Use the same schema options when reading and writing. Migration `[n]` transforms
schema `n` into `n + 1` and returns a table. Reading migrates in memory; explicitly
write to commit. A newer save schema cannot be read or overwritten by older code.
Tables must contain JSON-compatible values, not functions, nodes, cyclic graphs
or native objects. Defaults do not replace application-specific validation.

## Files, directories and streaming

| Method | Purpose |
| --- | --- |
| `read(filename, options)` / `write(filename, value, options)` | Main API for progress, preferences and arbitrary file bytes |
| `exists(filename)` | Check whether the primary or backup exists |
| `delete(filename, options)` | Delete the selected document and recovery companions |
| `createDirectory(path)` | Explicitly create an empty folder inside this scope; omit path for the scope itself |
| `listDirectories(path)` | Sorted immediate folder names; default is this scope |
| `listFiles(path, recursive)` | Sorted relative file paths, hiding temporary/redundant backups |
| `openFile(filename, mode)` | Streaming LOVE File handle; `r`, `w` or `a`; caller closes it |
| `scopeDirectory()` | Absolute device path of this scope under `saves` |
| `directory()` | Absolute application save directory, retained for compatibility |
| `filePath(filename)` | Virtual path for other LOVE APIs; resolves an existing legacy file if needed |

```lua
assert(shooter:createDirectory('profiles/empty'))
for _, name in ipairs(assert(shooter:listDirectories())) do
    print(name)
end

local stream = assert(shooter:openFile('logs/session.txt', 'a'))
assert(stream:write('Checkpoint reached\n'))
assert(stream:flush())
assert(stream:close())
```

Whole-file raw reads/writes default to 64 MiB (`maxFileBytes`, `0` disables the
limit); structured documents default to 8 MiB (`maxBytes`). Streaming avoids
buffering the whole file and bypasses backup publication for direct `w`/`a`
operations. Appending an old raw file imports its previous bytes in 64 KiB chunks.

Paths are relative to the scope. Traversal, absolute paths, control characters,
Windows reserved device names and `.tmp`/`.bak` recovery suffixes are rejected.
Scope paths can contain nested categories and ordinary folder names. Avoid using
the same path as both a folder and a file.

## Recovery and compatibility

New named JSON documents are written to exactly the requested filename, with
`<filename>.bak` retaining the previous verified generation. JSON uses a versioned
envelope with a SHA-256 checksum, not just the user's table text. Writes flush a
temporary file, verify it and publish it; a failed publish attempts rollback.
Reads select the most recent valid generation. A damaged primary can recover its
backup; two damaged generations report an error. Checksums are not encryption.

Raw writes retain bytes verbatim and keep one previous backup. Raw recovery can
find a missing primary but cannot detect format-specific corruption. Multiple
simultaneous writers and filesystem power-loss durability are outside this API.

Old extensionless slots remain supported: `read('progress')` / `write('progress',
table)` use the previous `progress.a.json` / `progress.b.json` convention. Prefer
explicit filenames in new code. `save/load/remove`, `writeFile/readFile/removeFile`
and `fileExists` remain compatibility entry points. The latter file methods always
handle original bytes, regardless of extension. Old raw files under `files/<scope>`
remain readable; new raw writes go under `saves/<scope>`. Listings merge both roots,
new files take priority and explicit raw deletion clears both copies.

The old `settings` wrapper is optional compatibility support for dirty tracking:
`data:settings('settings.json', options)` or `data:settings({ file = 'settings.json',
defaults = {...} })`. It offers get/set/save, but is not needed for preferences.
The Starter uses ordinary tables and the common read/write API. Its scene-owned
migration copies earlier progress/preferences slots to named JSON files once,
without deleting old slots or overwriting an existing named document.

## Persistent storage on the PC

The main project uses `%APPDATA%\LOVE\katsa-engine\`. All its scene categories
are under `saves/`. Removing or replacing the source/archive does not delete this
directory. Generated games use their own stable identity from
`source/game/data/project.lua`; keep it unchanged across updates. A title or game
folder can change without moving saves when identity stays the same.

```text
python tools/project/createProject.py ../MyGame-v2 --name my-game --identity my-stable-game
```

Shared categories are shared within the same application's identity and OS user,
not across unrelated games or cloud accounts. The former independent Starter's
files remain in `katsa-starter-game`; removing its duplicate project directory did
not delete that directory. See [save data](saveData.md) and [new games](newGame.md).

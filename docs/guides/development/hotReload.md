# Hot reload

Edit a file, save, and the running game picks it up. Start the development host with the flag
(or `KATSA_HOTRELOAD=1`):

```
xvfb-run -a luajit tools/dev/katsa.lua . --hot-reload      # Linux; on Windows run katsa.exe --hot-reload
```

| Changed file | What happens |
| --- | --- |
| `assets/locales/*.lua` | the language is read again, Labels update in place |
| `assets/tilesets/*.lua` | every TileMap reloads its tileset, cells stay |
| textures `.png` `.jpg` | the pixels are replaced in the loaded textures (same size); another size re-creates the scene |
| scene scripts, XML animations, shaders `.glsl`, other scene assets | the scene is created again from disk: new code and data, window stays open |
| `source/engine`, `source/katsa`, `source/plugins` | logged only; engine classes cannot be swapped under live objects, restart the program |

The watcher polls modification times and sizes (a few hundred files every half second), waits 0.3 s after the last
change so editors can finish writing, and applies a burst of edits together. A scene opened from a game folder joins
the watch list. Archives never change, so a packaged game does nothing. Messages go to the log with the prefix
`[hot reload]`; a failing restart is recorded in the journal and the error screen shows it.

## Example

```
luajit tools/dev/katsa.lua . --hot-reload
```

Open `assets/locales/en.lua`, change a string and save: the open scene shows the new text a moment later,
without a restart. Change a scene script and the scene is created again from disk.
Limits: game state is not kept on a scene restart (position, score), and shaders cause a scene restart rather than an
in-place rebuild. `source/engine/debug/hotReload.lua` has the details; test: `v108_7/hotReload.lua`.

# Projects and scenes

Katsa runs two kinds of things: a **scene** (one folder or archive with `conf.lua` and
`main.lua`) and a **project** (a folder or archive with a `conf.lua`). The engine itself ships no
scenes; the example collection lives in its own repository,
[katsa-engine-examples](https://github.com/falterize/katsa-engine-examples), and is an ordinary
project.

## Running

Run these from the engine folder:

| Command | What starts |
| --- | --- |
| `luajit tools/dev/katsa.lua .` | Nothing to run: a message in the window and in the console. |
| `luajit tools/dev/katsa.lua path/to/scene` | One scene (a folder or `.zip`/`.katsa` archive). |
| `luajit tools/dev/katsa.lua path/to/project` | The project: its start scene, other scenes in its folder. |

Drop a scene or project archive on the window to switch to it. Add `--shared <folder>` (repeatable)
to give a scene more `shared://` folders.

## A project

`conf.lua` returns the window settings and the project's own keys (the full list is in
[conf.lua](conf.md)):

```lua
return {
    identity = 'my-game',
    title = 'My Game',
    startScene = 'scenes/menu',      -- scene folder or id
    scenes = 'scenes',               -- default; every scene folder inside belongs to the project
    sharedAssets = { 'extra/assets' },
    plugins = { ik = true },         -- for every scene; a scene can set one to false
}
```

The engine mounts the project over its own files. Its `game/` modules and `assets/` resolve next to
the engine's shaders, fonts and fallback textures; on a name clash the engine's file wins. The
examples project is exactly this: `conf.lua`, `game/` (scenes, selection menu) and `assets/`.

If the project names no start scene, or the scene fails to load, the window shows "Could not start a
scene. Check the console for details." and the console says why. Scenes switch to each other by path
or by id with `manager:switch`.

## shared:// folders

`shared://textures/x.png` looks in the engine's `assets` first, then in each folder of
`sharedAssets` and `--shared`, in order; the first folder that holds the file wins. Use `shared://`
in scenes you want to run on their own. A scene that writes plain `assets/...` paths only works
inside a project that provides them.

## One scene or a project?

A scene started on its own has no project, so it cannot offer other scenes. Put scenes that should
know each other in a project.

<!-- book:nav -->
---
**Katsa book** · chapter 1, First steps · page 1 of 8

[Contents](README.md) · [conf.lua →](conf.md)
<!-- /book:nav -->

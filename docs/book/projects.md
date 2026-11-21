# Projects and scenes

Katsa runs two kinds of things: a **scene** (one folder or archive with `settings.lua` and
`main.lua`) and a **project** (a folder or archive with a `conf.lua`). The engine itself ships no
scenes; the example collection lives in its own repository,
[katsa-engine-examples](https://github.com/falterize/katsa-engine-examples), and is an ordinary
project.

## Running

Run these from the engine folder:

| Command | What starts |
| --- | --- |
| `luajit tools/dev/katsa.lua .` | Nothing to run: a black window and a console message. |
| `luajit tools/dev/katsa.lua path/to/scene` | One scene (a folder or `.zip`/`.katsa` archive). |
| `luajit tools/dev/katsa.lua path/to/project` | The project: its start scene, other scenes in its folder. |

Drop a scene or project archive on the window to switch to it. Add `--shared <folder>` (repeatable)
to give a scene more `shared://` folders.

## A project

`conf.lua` returns window settings and the project's own keys:

```lua
local Config = require('source.engine.core.windowConfig')
local project = require('game.data.project') -- title, identity, window size ...

function katsa.conf(settings)
    Config.apply(settings, project)
    settings.startScene = 'game/scenes/menu'   -- scene folder to start (omit: pick from a list)
    settings.scenes = 'game/scenes'            -- every scene folder inside belongs to the project
    settings.sharedAssets = { 'extra/assets' } -- more shared:// folders (relative or absolute)
end
```

The engine mounts the project over its own files. Its `game/` modules and `assets/` resolve next to
the engine's shaders, fonts and fallback textures; on a name clash the engine's file wins. The
examples project is exactly this: `conf.lua`, `game/` (scenes, selection menu) and `assets/`.

When a project lists several scenes and names no start scene, a plain list opens (Up/Down, Enter or a
click). Scenes switch to each other by path or by ID with `manager:switch`.

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
**Katsa book** · chapter 1, First steps · page 1 of 7

[Contents](README.md) · [Getting started →](../guides/development/gettingStarted.md)
<!-- /book:nav -->

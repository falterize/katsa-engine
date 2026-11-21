# conf.lua

Every game, project and scene has one `conf.lua`. It is a plain Lua file that returns a table. This
page lists every key. Everything is optional except `identity` of a game or project.

```lua
return {
    -- application (game or project; a scene run on its own may set these too)
    identity = 'my-game',          -- save folder name (Katsa/<identity>); never change it
    title = 'My Game',             -- window title
    version = '1.0.9a',            -- engine version it was made for; a mismatch only warns
    frameRateLimit = 0,            -- 0 = uncapped, otherwise frames per second
    console = true,                -- console window (Windows)
    externalStorage = true,        -- save to external storage (Android)
    window = {
        width = 1280, height = 720, minwidth = 320, minheight = 240,
        resizable = true, borderless = false,
        fullscreen = false, fullscreentype = 'desktop', display = 1,
        x = nil, y = nil,          -- nil: the system chooses
        vsync = false,             -- true, false or 'adaptive'
        msaa = 0, depth = 24, stencil = 8,
        highdpi = true, usedpiscale = true,
    },
    audio = { mic = false, mixwithsystem = true },
    modules = { physics = true, video = false },

    -- project: scenes and assets
    startScene = 'game/scenes/menu',   -- scene folder or id; none: a message in the console
    scenes = 'game/scenes',            -- folder of scenes (default: scenes/)
    sharedAssets = { 'extra', '/abs/folder' },  -- more shared:// folders after the engine's

    -- scene (plugins above also work here)
    nodes = { 'vehicle' },             -- node types private to the scene
    plugins = { ik = true, pathfinding = false }, -- project: for every scene; scene: true adds,
                                       -- false removes a project plugin for this scene
    runInBackground = false,           -- keep updating when the window loses focus
    server = 'server.main',            -- dedicated server entry (`--server`)
}
```

Menu data (`id`, `category`, `tags`, `description`) lives in the scene's `menu-settings.lua`.

## Which conf counts

| Started as | Window and application keys | Scenes, plugins |
| --- | --- | --- |
| Project (`conf.lua`, no `main.lua`) | the project's | the project's, then each scene's |
| Scene (`conf.lua` + `main.lua`) on its own | the scene's (`identity`, `title`, `window`, `audio`, `modules`, `console`, `externalStorage`) | the scene's |
| Scene inside a project | the project's: the window exists before any scene loads | the scene's, over the project's |
| Game (own `main.lua`, own copy of the engine) | its own | its own |

The engine's own `conf.lua` is the base of every project and scene run on it, so an unnamed `identity`
falls back to `katsa-engine`.

## Plugins

`plugins = { name = true | false }` everywhere. A project turns plugins on for all scenes; a scene
can add more or set one to `false` for itself. An unknown plugin name is an error.

## What is not in conf.lua

Anything that is not technical setup is code in the scene, written where the scene builds its world:

| Was in conf | Now |
| --- | --- |
| `physics = { backend = 'jolt' }` | `scene:createPhysics3D({ backend = 'jolt' })` |
| `physics2D = { ... }` | `scene:createPhysics2D({ ... })` |
| `gravity`, `gravityDirection` | options of `createPhysics2D` / `createPhysics3D` |
| `world = { sky = ..., ambient = ... }` | `scene.world:configure({ sky = { enabled = false } })` |
| `assets = { stone = { path = ... } }` | `scene.resources:define('stone', { path = ... })` |
| `layoutVersion`, `catalog`, `enabled`, `gammacorrect` | gone |

A scene's conf may still hold its own constants (any other key); the scene reads them through
`scene.settings`. The removed keys above are reported as errors, so old scenes fail loudly.

<!-- book:nav -->
---
**Katsa book** · chapter 1, First steps · page 2 of 8

[← Projects and scenes](projects.md) · [Contents](README.md) · [Getting started →](../guides/development/gettingStarted.md)
<!-- /book:nav -->

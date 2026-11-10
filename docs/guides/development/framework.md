# Framework and scenes

main.lua forwards katsa events to SceneManager. Menu, Game and Pause are separate scene classes. Game uses reusable engine modules and independent sceneContent/sceneUI modules. Demo builders live in examples/labs, with separate interface, simulation and dayCycle modules.

SceneManager supports switch, push, pop and deferred requestSwitch. Physical contact callbacks queue transitions rather than destroying a World3D during solver updates. Scenes own resource scopes, audio scopes, UI, input and render targets. Exit resets captures and time scale. Release destroys world/UI nodes and renderer resources.

update(dt, realDt) separates scaled simulation time from real-time UI and camera input. Pause stops simulation and scene audio. Focus/visibility loss clears captures; resize updates safe-area fitting, UI density and render targets.

Input checks screen UI, reserved joystick, world UI, then 3D click/camera areas. Each pointer retains its capture until release/cancel. UI drags scroll without activating buttons; taps activate on release. WASD and Q/E control the free camera; touch layout belongs to the scene.

The .katsa file is a ZIP with main.lua at its root. All source modules, assets, dependencies and documentation ship inside. Source CCode containers are not required to run the game.

## Example

```lua
-- A scene factory receives the manager and returns a table with optional hooks.
local function createPause(manager)
    return {
        update = function(self, dt, realDt) end,
        draw = function(self) end,
        exit = function(self) print('pause closed') end,
    }
end

manager:push(createPause)          -- stacked above the current scene (which is paused)
manager:pop()                      -- back to the scene below
manager:switch(createPause)        -- replaces the whole stack
manager:requestSwitch(createPause) -- the same, but safe inside physics callbacks
```

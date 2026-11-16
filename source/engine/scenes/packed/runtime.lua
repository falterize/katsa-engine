local Cleanup = require('source.engine.core.cleanup')
local Loader = require('../loader')
local Systems = require('../systems')
local WorldView = require('./worldView')

-- The scripts of a prefab scene running inside the scene that holds a copy ("a scene in a scene").
-- A prefab scene whose `main.lua` has a `build` hook (see scene.lua) keeps the rest of the usual
-- scene lifecycle for every copy: `create(scene, context)` once, then `update2D`, `update` and
-- `update3D` every frame, `destroy` when the copy is destroyed, plus the modules of its
-- `systems/` folder. `scene` is the host scene with its own `world` (WorldView), `resources`,
-- `settings`, `package`, `systems` and `node` (the copy's Node3D).
local Runtime = {}
Runtime.__index = Runtime

-- Starts the scripts for the copy `node` (packed.scripted: the scene has a `build` hook and something to run).
-- host: the scene that holds the copy (may be nil, e.g. a headless server world).
-- ui: the copy's World2D when the prefab has one; scripts get one on first use otherwise.
function Runtime.start(packed, world, node, host, ui)
    local package = packed.package
    local lifecycle = package:require('main')
    local resources =
        world.resources:scope(Loader.manifest({}, package.settings.assets), package.paths)
    local scope
    scope = {
        node = node,
        world2d = function()
            if not ui or ui.destroyed then
                ui = world:create('World2D', {}, node)
            end
            return ui
        end,
        paths = package.paths,
        context = { resources = resources, id = package.id, aliases = {} },
    }
    local scene = setmetatable({
        world = WorldView.new(world, scope),
        resources = resources,
        settings = package.settings,
        package = package,
        node = node,
        host = host,
    }, { __index = host or {} })
    -- `scene:world2d()`: the copy's own World2D (HUD and 2D nodes), made on first use.
    scene.world2d = function()
        return scope.world2d()
    end
    scene.systems = Systems.new(scene)
    local self = setmetatable({ scene = scene, lifecycle = lifecycle, resources = resources }, Runtime)
    self.state = lifecycle.create(scene, package) or {}
    Systems.discover(scene, package, self.state, lifecycle.systems)
    node:onDestroy(function()
        self:release()
    end)
    return self
end

function Runtime:update(dt)
    local lifecycle, state, systems = self.lifecycle, self.state, self.scene.systems
    lifecycle.update2D(state, dt, dt)
    systems:update2D(dt, dt)
    lifecycle.update(state, dt)
    systems:update(dt)
    lifecycle.update3D(state, dt)
    systems:update3D(dt)
end

function Runtime:release()
    if self.released then
        return
    end
    self.released = true
    Cleanup.run({
        function()
            self.lifecycle.destroy(self.state)
        end,
        function()
            self.scene.systems:release()
        end,
        function()
            self.resources:release()
        end,
    })
end

return Runtime

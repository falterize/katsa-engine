local Physics = require('source.engine.physics')
local Game = require('game.runtime.game')
local Catalog = require('game.examples.catalog')
local GLB = require('source.engine.import.glb')

local Tests = {}
Tests.__index = Tests

function Tests.new(manager)
    io.stdout:setvbuf('no')
    katsa.window.setMode(810, 456, { vsync = 0, depth = 24, stencil = 8 })
    return setmetatable({ manager = manager }, Tests)
end

function Tests:update() end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true

    local scope = self.manager.resources:scope()
    for _, path in ipairs({
        'game/scenes/models/assets/models/animated.glb',
        'assets/models/examples/skinRibbon.glb',
    }) do
        local model = GLB.load(path, scope)
        assert(#model.nodes > 0, 'Legacy GLB reader returned no nodes')
        model:update(0)
    end
    scope:release()

    local zones = {
        'original',
        'models',
        'physics',
        'collisionModels',
        'flyingAudio',
        'nightPlayer',
        'nodes',
        'shadows',
        'combined',
        'lights',
        'lights32',
        'objects',
    }
    for zone in pairs(Catalog) do
        zones[#zones + 1] = zone
    end
    table.sort(zones)
    local previous = Physics.backends.default
    local scenes = 0
    for _, backend in ipairs({ 'oimo', 'jolt' }) do
        Physics.setDefaultBackend(backend)
        for _, zone in ipairs(zones) do
            katsa.math.setRandomSeed(384)
            math.randomseed(384)
            local scene = assert(self.manager:switch(Game.new, zone))
            for _ = 1, 3 do
                self.manager:update(1 / 60)
            end
            self.manager:draw()
            katsa.graphics.present()
            local capture = scene.renderer.canvas:newImageData()
            capture:release()
            scenes = scenes + 1
            katsa.event.pump()
            print('PASS STRUCTURE SCENE', backend, zone)
        end
    end
    Physics.setDefaultBackend(previous)
    self.manager:switch(require('game.runtime.nodeCatalog').new)
    self.manager:update(1 / 60)
    self.manager:draw()
    self.manager:switch(require('game.runtime.menu').new)
    assert(#self.manager.journal.entries == 0, 'Scene/module migration produced journal errors')
    print('STRUCTURE CHECKS COMPLETE', scenes, 'scenes, legacy GLB readers and node catalog')
    katsa.event.quit()
end

return Tests

local P = {}
P.__index = P

function P.new(manager)
    love.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    local scene = manager:switch(require('source.game.runtime.game').new, 'combined')
    scene.world.lighting.gizmos.enabled = false
    local m = require('source.engine.math.math3d')
    local original = m.normalMatrix
    local self = setmetatable({ scene = scene, frame = 0, normals = 0, total = 0 }, P)
    m.normalMatrix = function(...)
        self.normals = self.normals + 1
        return original(...)
    end
    self.original, self.math = original, m
    return self
end

function P:update() end

function P:draw()
    local start = love.timer.getTime()
    for _, o in ipairs(self.scene.world.objects) do
        self.scene.world:updateObject(o)
    end
    self.scene.renderer:draw(self.scene.world, self.scene.camera, 0)
    self.frame = self.frame + 1
    if self.frame > 3 then
        self.total = self.total + (love.timer.getTime() - start) * 1000
    end
    if self.frame == 13 then
        print(
            string.format(
                'Combined / 640x360 / 10 measured submissions: %.3f ms average; derived normal recomputations %d',
                self.total / 10,
                self.normals
            )
        )
        self.math.normalMatrix = self.original
        love.event.quit()
    end
end

return P

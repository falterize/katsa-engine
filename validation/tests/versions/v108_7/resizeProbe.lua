-- Diagnostic: resizes the window under a running scene and prints how far the scene UI follows.
--   KATSA_SCENE=multiplayerCars xvfb-run -a luajit tools/dev/katsa.lua . --test-v108.7.resize
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    local self = setmetatable(Previous.new(manager), Tests)
    self.frame = 0
    return self
end

function Tests:report(tag)
    local scene = self.scene
    local w, h = katsa.graphics.getDimensions()
    print('RESIZE', tag, 'window', w, h, 'ui', scene.ui.width, scene.ui.height, scene.ui.scale)
end

function Tests:update()
    self.frame = self.frame + 1
    if self.frame == 1 then
        self.scene = assert(
            self.manager:switch(
                require('source.game.runtime.game').new,
                os.getenv('KATSA_SCENE') or 'multiplayerCars'
            )
        )
    end
end

function Tests:draw()
    local frame = self.frame
    if frame == 30 then
        self:report('before')
    elseif frame == 31 then
        local platform = katsa.platform
        platform.sdl.SDL_SetWindowSize(platform.window, 800, 500)
    elseif frame == 33 then
        self:report('2 frames after')
    elseif frame == 60 then
        self:report('later')
        katsa.event.quit()
    end
end

return Tests

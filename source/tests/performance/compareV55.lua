-- Same controlled workload runs in extracted v49 and current source.
local P = {}
P.__index = P

function P.new(manager)
    love.window.setVSync(0)
    local scene = manager:switch(require('source.game.runtime.game').new, 'combined')
    scene.world.lighting.gizmos.enabled = false
    scene.showStats = false
    local self = setmetatable(
        { scene = scene, frame = 0, case = 1, sums = {}, sizes = { { 640, 360 }, { 1280, 720 } } },
        P
    )
    self:resize()
    local ui = scene.ui
    local original = ui.draw
    ui.draw = function(owner, ...)
        local t = love.timer.getTime()
        local result = original(owner, ...)
        self.uiTime = (self.uiTime or 0) + (love.timer.getTime() - t) * 1000
        return result
    end
    return self
end

function P:resize()
    local size = self.sizes[self.case]
    love.window.setMode(size[1], size[2], { vsync = 0, depth = 24, stencil = 8 })
    self.scene:resize(unpack(size))
    collectgarbage('collect')
end

function P:update() end

function P:draw()
    self.uiTime = 0
    local t = love.timer.getTime()
    self.scene:update(1 / 60, 1 / 60)
    local update = (love.timer.getTime() - t) * 1000
    t = love.timer.getTime()
    self.scene:draw()
    local submit = (love.timer.getTime() - t) * 1000
    love.graphics.flushBatch()
    local data = self.scene.renderer.canvas:newImageData()
    data:release()
    local synced = (love.timer.getTime() - t) * 1000
    self.frame = self.frame + 1
    if self.frame > 3 then
        local s = self.scene.renderer.stats
        local values = {
            update = update,
            submit = submit,
            synced = synced,
            ui = self.uiTime,
            prepare = s.cullingMilliseconds or 0,
            lights = s.lightSelectionMilliseconds or 0,
            main = s.mainSubmissionMilliseconds or 0,
        }
        for key, value in pairs(values) do
            self.sums[key] = (self.sums[key] or 0) + value
        end
    end
    if self.frame == 13 then
        local s = self.scene.renderer.stats
        local values = {}
        for key, value in pairs(self.sums) do
            values[#values + 1] = string.format('%s=%.3fms', key, value / 10)
        end
        table.sort(values)
        print(
            string.format(
                'COMPARE %dx%d objects=%d candidates=%d lights=%d density=%.2f MSAA=%d shadows=%s | %s',
                self.sizes[self.case][1],
                self.sizes[self.case][2],
                s.objects,
                #self.scene.world.objects,
                s.lights,
                self.scene.renderer.density or 1,
                self.scene.renderer.actualMSAA or 0,
                tostring(self.scene.world.lighting.shadows.enabled),
                table.concat(values, ' ')
            )
        )
        if self.case == #self.sizes then
            love.event.quit()
            return
        end
        self.case = self.case + 1
        self.frame = 0
        self.sums = {}
        self:resize()
    end
end

return P

-- Diagnostic: a running player turns into a ragdoll; prints hips speed and the lowest limb point.
local Previous = require('validation.tests.versions.v107.physics2D')
local Application = require('game.runtime.application')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable(Previous.new(manager), Tests)
end

function Tests:update() end

function Tests:draw()
    if self.done then
        return
    end
    self.done = true
    local scene = Application.new(self.manager, 'stareShooter')
    scene:load()
    for _ = 1, 30 do
        scene:update(1 / 60, 1 / 60)
    end
    local ragdoll = scene.demo.ragdoll
    local body = scene.demo.player.body.node
    scene.demo.player.body:setVelocity({ 0, 0, tonumber(os.getenv('SPEED') or 9) })
    ragdoll:toggle()
    local names = { 'Hips', 'Chest', 'Head', 'UpperArmL', 'ForearmL', 'HandL', 'UpperArmR', 'ForearmR', 'HandR', 'ThighL', 'ShinL', 'FootL', 'ThighR', 'ShinR', 'FootR' }
    for frame = 1, 900 do
        scene:update(1 / 60, 1 / 60)
        if frame % 60 == 0 then local sec = frame / 60
            local hips = ragdoll.node:getBody('Hips')
            local v = hips.physics:getVelocity({})
            local low, who = 1e9, ''
            for _, n in ipairs(names) do
                local b = ragdoll.node:getBody(n)
                local m = b:getRenderWorldMatrix()
                local c = b.collider or (b.children and b.children[1])
                local r = (c and c.radius) or 0
                local h = (c and c.height) or 0
                -- Lowest point of the capsule: centre - half the axis' vertical reach - radius.
                local lowest = m[8] - math.abs(m[6]) * (h / 2) - r
                if lowest < low then
                    low, who = lowest, n
                end
            end
            local m = hips:getRenderWorldMatrix()
            print(string.format('t=%2ds hips x=%.2f y=%.2f z=%.2f speed=%.2f lowest capsule point=%.3f (%s)', sec, m[4], m[8], m[12], math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2), low, who))
        end
    end
    local dir = os.getenv('KATSA_SHOT')
    if dir then
        scene:draw()
        katsa.graphics.captureScreenshot(dir .. '/ragdoll.png')
        scene:draw()
    end
    os.exit(0)
end

return Tests

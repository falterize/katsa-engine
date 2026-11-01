-- Same-process, alternating production paths; fence once after each batch.
local T = {}
T.__index = T

function T.new(manager)
    io.stdout:setvbuf('no')
    katsa.window.setMode(1280, 720, { vsync = 0, depth = 24, stencil = 8 })
    return setmetatable({ manager = manager }, T)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    local g = katsa.graphics
    local UI = require('source.engine.ui')
    local Text = require('source.engine.ui.drawing.text')
    local Node = require('source.engine.nodes')
    local Variants = require('source.engine.graphics.pipeline.shaderVariants')
    local current = {
        drawNode = UI.drawNode,
        drawSelf = Node.getClass('UINode').drawSelf,
        drawLabel = Text.drawLabel,
        shader = Variants.get,
    }
    local function fixture(name)
        return assert(
            loadstring(katsa.filesystem.read('source/tests/fixtures/v101-' .. name .. '.lua'))
        )()
    end
    local oldText, oldVariants = fixture('text'), fixture('shaderVariants')
    local baselineUI = {}
    fixture('drawing')(baselineUI)
    -- Load the original UINode drawSelf without registering a duplicate class.
    local oldNodeSource = katsa.filesystem.read('source/tests/fixtures/v101-uiNode.lua')
    oldNodeSource =
        oldNodeSource:gsub("local UINode = Node.define%('UINode', 'Node'%)", 'local UINode = {}')
    local oldNode = assert(loadstring(oldNodeSource))()

    local function mode(baseline)
        UI.drawNode = baseline and baselineUI.drawNode or current.drawNode
        Node.getClass('UINode').drawSelf = baseline and oldNode.drawSelf or current.drawSelf
        Text.drawLabel = baseline and oldText.drawLabel or current.drawLabel
        Variants.get = baseline and oldVariants.get or current.shader
    end
    print('GPU', g.getRendererInfo())
    print('JIT', jit.status(), 'DPI', g.getDPIScale())
    print('case,round,version,mean batch ms including final GPU fence,mean CPU draw calls')
    for _, zone in ipairs({ 'combined', 'animationPhysicsLab', 'uiGallery', 'viewports' }) do
        for round = 1, 3 do
            for pass = 1, 2 do
                local baseline = (round % 2 == 1) == (pass == 1)
                mode(baseline)
                katsa.math.setRandomSeed(384)
                math.randomseed(384)
                local scene =
                    assert(self.manager:switch(require('source.game.runtime.game').new, zone))
                scene.showStats = false
                if zone == 'combined' then
                    scene.world.environment.shadows.enabled = false
                    scene.world.environment.debug.gizmos.enabled = false
                end
                local x, yaw = scene.camera.position[1], scene.camera.rotation[2]
                local calls, started
                local frames = tonumber(os.getenv('KATSA_AB_FRAMES') or 180)
                for frame = 1, frames + 60 do
                    if zone == 'combined' then
                        scene.camera.position[1] = x + math.sin(frame / 60) * 30
                        scene.camera.rotation[2] = yaw + math.sin(frame / 60) * 5
                    end
                    if frame == 61 then
                        local fence = scene.renderer.canvas:newImageData()
                        fence:release()
                        collectgarbage('collect')
                        calls = 0
                        started = katsa.timer.getTime()
                    end
                    katsa.event.pump()
                    self.manager:update(1 / 60)
                    self.manager:draw()
                    if frame > 60 then
                        calls = calls + g.getStats().drawcalls
                    end
                    g.present()
                end
                local fence = scene.renderer.canvas:newImageData()
                fence:release()
                print(
                    string.format(
                        '%s,%d,%s,%.3f,%.1f',
                        zone,
                        round,
                        baseline and 'v101' or 'v102',
                        (katsa.timer.getTime() - started) * 1000 / frames,
                        calls / frames
                    )
                )
            end
        end
    end
    mode(false)
    assert(#self.manager.journal.entries == 0, 'Runtime journal errors')
    print('A/B PROFILE COMPLETE')
    katsa.event.quit()
end

return T

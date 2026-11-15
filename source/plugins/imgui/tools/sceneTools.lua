-- Scene tools window: the toggles of the old Tools panel (animations, fog, sound, music,
-- billboards, light limit, view reset, time scale, shader effects) and the audio mixer.
local SceneTools = { id = 'sceneTools', title = 'Scene tools', key = 'f9' }

local GROUPS = { 'master', 'music', 'effects', 'ui' }

function SceneTools.new()
    return {}
end

function SceneTools.draw(ig, scene, _, host)
    local width, height = katsa.graphics.getDimensions()
    ig.setNextWindowPos(math.max(10, width - 350), 60)
    ig.setNextWindowSize(math.min(340, width * 0.4), math.min(520, height * 0.5))
    local visible, open = ig.begin('Scene tools', true)
    if visible then
        local _, changed
        changed, scene.demoAnimations = ig.checkbox('Animations (Space)', scene.demoAnimations)
        local fog = scene.world.environment.fog
        _, fog.enabled = ig.checkbox('Fog', fog.enabled)
        changed = ig.checkbox('Billboard motion', scene.billboardMotion)
        if changed then
            scene.billboardMotion = not scene.billboardMotion
        end
        local boards
        boards, _ = ig.checkbox('Billboards', scene.billboardsVisible)
        if boards then
            scene:toggleBillboards()
        end
        local effects
        effects, _ = ig.checkbox('Shader effects', scene.effectsEnabled)
        if effects then
            scene.effectsEnabled = not scene.effectsEnabled
            if scene.objectEffect then
                scene.objectEffect.enabled = scene.effectsEnabled
            end
            scene.uiEffect.enabled = scene.effectsEnabled
            scene:syncButtons()
        end
        ig.separator()
        if ig.button('Play sound') then
            scene:playSound()
        end
        ig.sameLine()
        local playing = scene.musicVoice and not scene.musicVoice.released and not scene.musicVoice.manualPause
        if ig.button(playing and 'Music: ON' or 'Music: OFF') then
            scene:toggleMusic()
        end
        ig.sameLine()
        if ig.button('Reset view') then
            scene.camera.position = { 0, 0, 0 }
            scene.camera.rotation = { 0, 0, 0 }
        end
        local settings = scene.world.environment.lightSettings
        local limits = { '12 lights', '32 lights' }
        local picked
        changed, picked = ig.combo('Light limit', settings.maxActiveLights == 32 and 2 or 1, limits)
        if changed then
            settings.maxActiveLights = picked == 2 and 32 or 12
        end
        local scale = scene.manager.time.scale
        local moved, value = ig.sliderFloat('Time scale', scale, 0, 2)
        if moved then
            scene.manager.time:setScale(value)
            scene.audio:update(scene.camera)
            scene:syncButtons()
        end
        if ig.collapsingHeader('Audio mixer', true) then
            for _, name in ipairs(GROUPS) do
                local slid, volume = ig.sliderFloat(name, scene.audio:getGroupVolume(name), 0, 1)
                if slid then
                    scene.audio:setGroupVolume(name, volume)
                    scene.audio:update(scene.camera)
                end
            end
            ig.textDisabled('Master multiplies every group; UI audio continues while paused.')
        end
    end
    ig.finish()
    if not open then
        host:close(SceneTools.id)
    end
end

return SceneTools

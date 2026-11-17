local bit = require('bit')

-- The scene's main bar: a fixed strip along the top with the buttons the old Navigation header
-- had (Menu, Pause, Stats, Debug) plus the Explorer and Properties windows. It is
-- shown while `scene.navigationVisible` is not false (presentation.navigation = false hides it).
local Toolbar = {}

local HEIGHT = 40

local function flags(ig)
    local C = ig.C
    return bit.bor(
        C.ImGuiWindowFlags_NoTitleBar,
        C.ImGuiWindowFlags_NoResize,
        C.ImGuiWindowFlags_NoMove,
        C.ImGuiWindowFlags_NoScrollbar,
        C.ImGuiWindowFlags_NoSavedSettings,
        C.ImGuiWindowFlags_NoCollapse
    )
end

-- A button that stays highlighted while its window is open.
local function toggle(ig, label, active)
    if active then
        ig.pushColor('Button', 0.16, 0.42, 0.62, 1)
    end
    local pressed = ig.button(label)
    if active then
        ig.popColor()
    end
    return pressed
end

local function click(scene)
    scene.audio:play('assets/audio/effects/click.wav', { group = 'ui', timeScaled = false })
end

function Toolbar.height()
    return HEIGHT
end

function Toolbar.draw(ig, scene, host)
    if scene.navigationVisible == false then
        return
    end
    local width = katsa.graphics.getDimensions()
    ig.setNextWindowPos(0, 0, ig.C.ImGuiCond_Always)
    ig.setNextWindowSize(width, HEIGHT, ig.C.ImGuiCond_Always)
    ig.setNextWindowBgAlpha(0.92)
    local visible = ig.begin('##katsaToolbar', nil, flags(ig))
    if visible then
        if ig.button('Menu') then
            click(scene)
            scene.manager:switch(require('game.runtime.menu').new)
        end
        ig.sameLine()
        if ig.button('Pause') then
            click(scene)
            scene.pauseMenu:toggle()
        end
        ig.sameLine()
        if toggle(ig, 'Stats', host:isOpen('stats')) then
            host:toggle('stats')
        end
        ig.sameLine()
        if toggle(ig, 'Debug', host:isOpen('debug')) then
            host:toggle('debug')
        end
        ig.sameLine()
        if toggle(ig, 'Explorer', host:isOpen('explorer')) then
            host:toggle('explorer')
        end
        ig.sameLine()
        if toggle(ig, 'Properties', host:isOpen('properties')) then
            host:toggle('properties')
        end
    end
    ig.finish()
end

return Toolbar

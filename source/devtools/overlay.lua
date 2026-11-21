-- Stats and Console overlays (F3 / F6 / F1) and, in the full runtime, the Debug menu (F4) and its
-- legacy button. Installed by source/runtime/modules.lua; removing the module removes all of them.
local Overlay = { name = 'overlay' }
Overlay.__index = Overlay

function Overlay.install(scene)
    return setmetatable({
        scene = scene,
        -- Three fingers at once open the console: a phone has no F1.
        gesture = require('source.engine.debug.touchGesture').new(3),
    }, Overlay)
end

-- Hooks ---------------------------------------------------------------------------------------

function Overlay:created()
    local scene = self.scene
    local ui = scene._ui
    local Statistics = require('source.engine.debug.statistics.definitions')
    local Console = require('source.engine.debug.consolePanel')
    if scene.runtime ~= 'game' then
        local layer = ui:container({ size = { 1, 0, 1, 0 }, zIndex = 1000 }, ui.content)
        scene.statistics = Statistics.new(scene, layer)
        scene.console = Console.new(ui, layer)
        return
    end
    local presentation = scene.settings.presentation
    self.hidden = presentation and presentation.navigation == false
    scene.debugOverlay = require('source.engine.debug.menu').new(scene)
    local controls = ui:canvasGroup({
        position = { 0, 0, 0, 0 },
        size = { 0, 1280, 0, 720 },
        name = 'DebugControls',
        zIndex = 200,
    })
    scene.console = Console.new(ui, controls)
    scene.debugButton = ui:button({
        position = { 1, -12, 0, 64 },
        size = { 0, 110, 0, 34 },
        anchorPoint = { 1, 0 },
        textScaled = true,
        maxTextSize = 16,
        name = 'DebugToggle',
        visible = not self.hidden,
        _viewportAuthored = true,
        text = 'Debug / F4',
        fontSize = 22,
        backgroundColor = { 0.08, 0.16, 0.25 },
        backgroundTransparency = 1 - 0.95,
    }, controls)
    scene.debugButton:connect('press', function()
        if not scene:consume('toggleDebug') then
            scene.debugOverlay.visible = not scene.debugOverlay.visible
        end
    end)
    scene.statsLayer = ui:canvasGroup({
        name = 'StatsOverlay',
        size = { 1, 0, 1, 0 },
        zIndex = 100000,
        visible = false,
    })
    scene.statistics = Statistics.new(scene, scene.statsLayer)
    scene.statsScroll, scene.statsPanel = scene.statistics.panel.scroll, scene.statistics.panel.header
end

function Overlay:resize()
    self.scene.statistics.panel:resize()
end

function Overlay:update()
    local scene = self.scene
    local debugOverlay = scene.debugOverlay
    if debugOverlay and debugOverlay.visible and debugOverlay._syncDebug then
        debugOverlay._syncDebug()
    end
    scene.console:update()
end

function Overlay:beforeUI()
    local scene = self.scene
    if scene.statsLayer then
        -- The ImGui Stats window replaces the legacy panel.
        scene.statsLayer.visible = scene.showStats and not self.replaced
    end
    scene.statistics:sample()
end

function Overlay:pointerpressed(id)
    if self.gesture:press(id) then
        self.scene.console:toggle()
    end
    return false
end

function Overlay:pointerreleased(id)
    self.gesture:release(id)
end

Overlay.pointercancelled = Overlay.pointerreleased

function Overlay:keyUnhandled(key)
    local scene = self.scene
    if key == 'f3' then
        scene.showStats = not scene.showStats
    elseif key == 'f6' then
        scene.statistics:export(30)
    elseif key == 'f1' then
        scene.console:toggle()
    elseif key == 'f4' and scene.debugOverlay then
        -- Same path as the Debug button: the ImGui Debug window when it is attached.
        if not scene:consume('toggleDebug') then
            scene.debugOverlay.visible = not scene.debugOverlay.visible
        end
    else
        return false
    end
    return true
end

-- The Debug button hides while the editor panel is open.
function Overlay:editorToggled(opened)
    local button = self.scene.debugButton
    if button then
        button.visible = not opened and not self.hidden and not self.replaced
    end
end

function Overlay:imguiAttached()
    self.replaced = true
    if self.scene.debugButton then
        self.scene.debugButton.visible = false
    end
end

function Overlay:immersion(captured)
    local scene = self.scene
    self.hidden = captured
    if scene.debugButton then
        scene.debugButton.visible = not captured and not self.replaced
    end
    if captured then
        scene.showStats = false
        if scene.debugOverlay then
            scene.debugOverlay.visible = false
        end
    end
end

-- The Debug menu counts as open UI: gameplay input pauses while it is visible.
function Overlay:capturesInput()
    local debugOverlay = self.scene.debugOverlay
    return debugOverlay ~= nil and debugOverlay.visible == true
end

function Overlay:release()
    local scene = self.scene
    if scene.console then
        scene.console:release()
        scene.console = nil
    end
end

return Overlay

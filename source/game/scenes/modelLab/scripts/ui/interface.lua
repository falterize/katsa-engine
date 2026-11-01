local ipairs = require('source.engine.math.array').ipairs
local Mesh = require('source.engine.composition.mesh')
local Models = require('source.engine.import.models')
local Theme = require('source.engine.ui.theme')

local Interface = {}

function Interface.create(self)
    local scene, ui = self.scene, self.scene.ui
    local panel = ui:container({
        _viewportAuthored = true,
        name = 'ModelControls',
        position = { 0, 12, 0, 112 },
        size = { 0, 265, 0.66, -124 },
        backgroundColor = Theme.panel,
    }, ui.content)
    ui:create('UICorner', { radius = { 0, Theme.corner } }, panel)
    require('source.engine.ui.widgets.collapsible').create(
        scene,
        panel,
        'Models / bones / playback'
    )
    local body =
        ui:scroll({ size = { 1, 0, 1, 0 }, automaticLength = true, contentPadding = 8 }, panel)
    local y = 0

    local function button(text, callback)
        ui:button({
            position = { 0, 6, 0, y },
            size = { 1, -12, 0, 32 },
            fontSize = 12,
            text = text,
            backgroundColor = Theme.button,
            radius = Theme.corner,
            onPress = callback,
        }, body)
        y = y + 38
    end
    for _, name in ipairs({ 'Idle', 'Walk', 'Run', 'Jump', 'Fall', 'Wave' }) do
        button('Demo ' .. name, function()
            self.track = self.animator:transition('Demo ' .. name, 0.25)
            if not self._markerTracks[self.track] then
                self._markerTracks[self.track] = true
                self.track:connect('Marker', function()
                    self.markerCount = self.markerCount + 1
                end)
            end
        end)
    end
    button('Drop collision test cube', function()
        self.dropCount = (self.dropCount or 0) + 1
        local body = scene.world:create('Body3D', {
            name = 'TestDrop' .. self.dropCount,
            position = { -65, 110, 55 },
            collider = { shape = 'Box', size = { 6, 6, 6 } },
            restitution = 0.6,
        })
        Mesh.create(scene.world, {
            name = 'TestDropVisual' .. self.dropCount,
            size = { 6, 6, 6 },
            color = { 1, 0.15, 0.15, 1 },
        }, body)
    end)
    button('Surface material ON / OFF', function()
        self.appearance.enabled = not self.appearance.enabled
    end)
    button('Normal map ON / OFF', function()
        self.appearance.normalMap = self.appearance.normalMap == ''
                and 'assets/textures/materials/normal.png'
            or ''
    end)
    button('Emission weak / strong', function()
        self.appearance.emissionStrength = self.appearance.emissionStrength < 1 and 1.5 or 0.25
    end)
    button('Metalness .0 / .9', function()
        self.appearance.metalness = self.appearance.metalness > 0 and 0 or 0.9
    end)
    button('Model transparency 0 / .5 / 1', function()
        local root = self.multi.root
        root.transparency = root.transparency == 0 and 0.5 or root.transparency == 0.5 and 1 or 0
    end)
    button('Bone debug ON / OFF', function()
        self.animator.debugEnabled = not self.animator.debugEnabled
    end)
    button('Physics debug ON / OFF', function()
        scene.physics.debugEnabled = not scene.physics.debugEnabled
    end)
    button('Animation pause / resume', function()
        if self.track.state == 'Paused' then
            self.track:resume()
        else
            self.track:pause()
        end
    end)
    button('Inspect XBot hierarchy', function()
        scene.workspace:toggle(true)
        scene.workspace:select(self.model.root)
    end)
    button('Inspect multi-mesh model', function()
        scene.workspace:toggle(true)
        scene.workspace:select(self.multi.root)
    end)
    self.info = ui:text({
        position = { 0, 6, 0, y },
        size = { 1, -12, 0, 74 },
        fontSize = 11,
        text = 'Procedural demonstration clips; XBot FBX contains no motion. Green lines: bones. Purple: attachments.',
    }, body)
end

return Interface

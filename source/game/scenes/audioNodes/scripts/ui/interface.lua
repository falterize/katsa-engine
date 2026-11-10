local unpack = require('source.engine.math.array').unpack
local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs

local Interface = {}

function Interface.create(self)
    local ui = self.scene.ui
    local panel = ui:create('Frame', {
        name = 'AudioLab',
        _viewportAuthored = true,
        position = { 0.5, 0, 0.58, 0 },
        size = { 0.78, 0, 0.68, 0 },
        anchorPoint = { 0.5, 0.5 },
        backgroundColor = { 1, 1, 1 },
    }, ui.content)
    require('source.engine.ui.widgets.collapsible').create(self.scene, panel, 'Audio controls')
    self.panel = panel
    self.presetButtons = {}
    self.actionButtons = {}
    ui:create('UICorner', { radius = { 0, 18 } }, panel)
    ui:create('Ramp', {
        points = {
            { time = 0, value = { 0.035, 0.085, 0.15, 0.98 } },
            {
                time = 1,
                value = { 0.09, 0.18, 0.26, 0.98 },
            },
        },
        rotation = 35,
    }, panel)
    ui:create(
        'UIStroke',
        { target = 'Border', thickness = { 0, 2 }, color = { 0.25, 0.7, 0.95, 1 } },
        panel
    )
    local title = ui:text({
        position = { 0, 18, 0, 12 },
        size = { 1, -36, 0, 42 },
        text = 'Sound nodes / effect listening lab',
        fontSize = 26,
        textScaled = true,
        maxTextSize = 26,
    }, panel)
    ui:create('Ramp', {
        target = 'Text',
        points = {
            { time = 0, value = { 0.6, 0.95, 1, 1 } },
            { time = 1, value = { 1, 0.8, 0.35, 1 } },
        },
    }, title)
    ui:create('UIStroke', { target = 'Text', thickness = { 0, 1 } }, title)
    local body = ui:scroll({
        position = { 0, 12, 0, 62 },
        size = { 1, -24, 1, -74 },
        length = 420,
        backgroundTransparency = 1,
    }, panel)
    self.body = body
    local presets = {
        { 'Dry' },
        { 'Reverb', 'SoundReverb' },
        { 'Echo', 'SoundEcho' },
        { 'Chorus', 'SoundChorus' },
        { 'Distortion', 'SoundDistortion' },
        { 'Low pitch', 'SoundPitch', 0.7 },
        { 'High pitch', 'SoundPitch', 1.4 },
        { 'Low-pass', 'SoundFilter' },
        { 'Group reverb', 'Group' },
    }
    for i, preset in ipairs(presets) do
        local button = ui:button({
            position = { ((i - 1) % 3) / 3, 4, 0, math.floor((i - 1) / 3) * 54 },
            size = { 1 / 3, -8, 0, 44 },
            text = preset[1],
            fontSize = 20,
            textScaled = true,
            maxTextSize = 20,
            backgroundColor = { 0.12, 0.25, 0.34 },
            backgroundTransparency = 1 - 1,
        }, body)
        button:connect('press', function()
            self:choose(unpack(preset))
        end)
        button._audioControl = true
        self.presetButtons[#self.presetButtons + 1] = button
        ui:create('UICorner', { radius = { 0, 10 } }, button)
        ui:create(
            'UIStroke',
            { target = 'Border', thickness = { 0, 1 }, color = { 0.3, 0.55, 0.65, 1 } },
            button
        )
    end

    local function button(text, x, callback)
        local node = ui:button({
            position = { (x - 18) / 688, 4, 0, 168 },
            size = { 1 / 4, -8, 0, 42 },
            text = text,
            fontSize = 19,
            textScaled = true,
            maxTextSize = 19,
            backgroundColor = { 0.12, 0.25, 0.34 },
            backgroundTransparency = 1 - 1,
        }, body)
        if callback then
            node:connect('press', callback)
        end
        node._audioControl = true
        self.actionButtons[#self.actionButtons + 1] = node
        return node
    end
    button('Pause', 18, function()
        self.sound:pause()
    end)
    button('Resume / Play', 190, function()
        self.sound:play()
    end)
    button('Stop', 362, function()
        self.sound:stop()
    end)
    button('Playing true / false', 576, function()
        self.sound.Playing = not self.sound.Playing
    end)
    button('Enabled mute / unmute', 618, function()
        self.sound.Enabled = not self.sound.Enabled
    end)
    self.spatialButton = button('Spatial: OFF', 534, function()
        self.sound:stop()
        self.sound.spatial = not self.sound.spatial
        self.sound:play()
        self.spatialButton.text = self.sound.spatial and 'Spatial: ON' or 'Spatial: OFF'
    end)
    ui:text({
        position = { 0, 4, 0, 220 },
        size = { 0.33, -4, 0, 30 },
        text = 'Group volume',
        fontSize = 18,
        textScaled = true,
        maxTextSize = 18,
        align = 'left',
    }, body)
    do
        local node = ui:slider({
            position = { 0.34, 0, 0, 216 },
            size = { 0.66, -4, 0, 38 },
            min = 0,
            max = 1,
            value = 0.8,
        }, body)
        node:connect('changed', function(value)
            self.group.volume = value
        end)
    end
    ui:text({
        position = { 0, 4, 0, 270 },
        size = { 0.33, -4, 0, 30 },
        text = 'Playback speed',
        fontSize = 18,
        textScaled = true,
        maxTextSize = 18,
        align = 'left',
    }, body)
    do
        local node = ui:slider({
            position = { 0.34, 0, 0, 266 },
            size = { 0.66, -4, 0, 38 },
            min = 0.5,
            max = 2,
            value = 1,
        }, body)
        node:connect('changed', function(value)
            self.sound.playbackSpeed = value
        end)
    end
    self.status = ui:text({
        position = { 0, 4, 0, 320 },
        size = { 1, -8, 0, 96 },
        text = 'Select a preset to listen. No sound starts automatically.',
        fontSize = 17,
        align = 'left',
        verticalAlign = 'top',
    }, body)
    self.status.enabled = false
end

return Interface

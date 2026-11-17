local ipairs = require('source.engine.math.array').ipairs
local pairs = require('source.engine.math.array').pairs

local Controls = {}

function Controls.build(lab)
    local scene, ui = lab.scene, lab.scene.root:find('World3D/World2D')
    lab.panel = ui:container({
        _viewportAuthored = true,
        name = 'ParticleControls',
        position = { 0, 12, 0, 112 },
        size = { 0, 310, 1, -206 },
        backgroundColor = { 0.025, 0.05, 0.08 },
    }, ui.content)
    lab.collapse = ui:button({
        _viewportAuthored = true,
        position = { 0, 12, 0, 74 },
        size = { 0, 210, 0, 32 },
        text = '− Particle controls',
        fontSize = 14,
    }, ui.content)
    lab.collapse:connect('press', function(node)
        lab.panel.visible = not lab.panel.visible
        node.text = lab.panel.visible and '− Particle controls' or '+ Particle controls'
    end)
    -- With ImGui the panel is a window and the collapse button is not needed.
    require('source.engine.ui.widgets.collapsible').adopt(scene, 'Particle controls', lab.panel, function()
        lab.collapse.visible = false
    end)
    lab.status = ui:text({
        position = { 0, 8, 0, 6 },
        size = { 1, -16, 0, 58 },
        fontSize = 12,
        align = 'left',
        text = 'Particle counters',
    }, lab.panel)
    lab.controlsBody = ui:scroll({
        position = { 0, 6, 0, 68 },
        size = { 1, -12, 1, -74 },
        length = 0,
        backgroundTransparency = 1,
    }, lab.panel)
    local body = lab.controlsBody
    local y = 0
    lab.tabs = {}
    lab.readouts = {}
    lab.buttons = {}
    lab.sliders = {}
    for i, e in ipairs(lab.emitters) do
        lab.tabs[i] = ui:button({
            position = { (i - 1) % 3 / 3, 3, 0, math.floor((i - 1) / 3) * 34 },
            size = { 1 / 3, -6, 0, 30 },
            text = e.name,
            fontSize = 12,
            backgroundColor = { 0.07, 0.14, 0.2 },
        }, body)
        lab.tabs[i]:connect('press', function()
            lab.selected = i
            lab.emitter = e
            lab.syncControls = true
        end)
    end
    y = 72

    -- `columns` buttons share one row (the ImGui window keeps rows that share a top).
    local function button(key, fn, column, columns)
        column, columns = column or 1, columns or 1
        local b = ui:button({
            position = { (column - 1) / columns, 3, 0, y },
            size = { 1 / columns, -6, 0, 30 },
            text = key,
            fontSize = 12,
            backgroundColor = { 0.07, 0.14, 0.2 },
        }, body)
        b:connect('press', function()
            fn()
            lab.syncControls = true
        end)
        lab.buttons[key] = b
        if column == columns then
            y = y + 34
        end
        return b
    end

    local function slider(key, text, min, max, get, set)
        local label = ui:text({
            position = { 0, 5, 0, y },
            size = { 1, -10, 0, 20 },
            text = text,
            fontSize = 12,
            align = 'left',
        }, body)
        y = y + 22
        local s = ui:slider({
            position = { 0, 3, 0, y },
            size = { 1, -6, 0, 28 },
            min = min,
            max = max,
            value = get(),
        }, body)
        s:connect('changed', function(value)
            set(value)
            lab.syncControls = true
        end)
        lab.sliders[key] = { node = s, label = label, get = get, text = text }
        y = y + 34
    end
    button('Inspect', function()
        local editor = scene:module('editor')
        if editor then
            editor:inspect(lab.emitter)
        end
    end, 1, 4)
    button('Emit', function()
        lab.emitter:emit(40)
    end, 2, 4)
    button('Clear', function()
        lab.emitter:clear()
    end, 3, 4)
    button('Reset', function()
        lab:restorePreset(lab.emitter)
    end, 4, 4)
    button('Enabled', function()
        lab.emitter.enabled = not lab.emitter.enabled
    end)
    button('Attraction', function()
        lab.emitter.attractionEnabled = not lab.emitter.attractionEnabled
    end)
    button('Collision', function()
        lab.emitter.collisionEnabled = not lab.emitter.collisionEnabled
    end)
    button('Unlit', function()
        lab.emitter.lightInfluence = lab.emitter.lightInfluence > 0 and 0 or 1
    end)
    button('Space', function()
        local e = lab.emitter
        e.simulationSpace = e.simulationSpace == 'World' and 'Local' or 'World'
    end, 1, 2)
    button('Blend', function()
        local next = { Alpha = 'Add', Add = 'Multiply', Multiply = 'Alpha' }
        lab.emitter.blendMode = next[lab.emitter.blendMode]
    end, 2, 2)
    slider('rate', 'Emission / second', 0, 150, function()
        return lab.emitter.rate
    end, function(v)
        lab.emitter.rate = v
    end)
    slider('gravity', 'Gravity multiplier', -1, 2, function()
        return lab.emitter.gravityScale
    end, function(v)
        lab.emitter.gravityScale = v
    end)
    slider('strength', 'Attraction acceleration', 0, 400, function()
        return lab.emitter.attractionStrength
    end, function(v)
        lab.emitter.attractionStrength = v
    end)
    slider('drag', 'Wind drag / second', 0, 5, function()
        return lab.emitter.drag
    end, function(v)
        lab.emitter.drag = v
    end)
    slider('Brightness', 'Particle brightness', 0, 4, function()
        return lab.emitter.brightness
    end, function(v)
        lab.emitter.brightness = v
    end)

    button('Move support', function()
        local node = lab.emitter.adornee or lab.emitter.parent
        node.position[1] = node.position[1] + 10
    end)
    body.length = y
    lab.addSettings = true
    lab.syncControls = true
end

function Controls.update(lab)
    local ui, e = lab.scene.root:find('World3D/World2D'), lab.emitter
    lab.panel.size = { 0, math.min(310, ui.width - 24), 1, -206 }
    if
        lab.syncControls
        or e._controlsEnabled ~= e.enabled
        or e._controlsSpace ~= e.simulationSpace
        or e._controlsBlend ~= e.blendMode
        or e._controlsAttraction ~= e.attractionEnabled
        or e._controlsCollision ~= e.collisionEnabled
        or e._controlsInfluence ~= e.lightInfluence
    then
        lab.syncControls = false
        e._controlsInfluence = e.lightInfluence
        e._controlsEnabled, e._controlsSpace, e._controlsBlend, e._controlsAttraction, e._controlsCollision =
            e.enabled, e.simulationSpace, e.blendMode, e.attractionEnabled, e.collisionEnabled
        for i, b in ipairs(lab.tabs) do
            b.backgroundColor = i == lab.selected and { 0.1, 0.38, 0.5 } or { 0.075, 0.14, 0.2 }
            b.text = i == lab.selected and '[' .. lab.emitters[i].name .. ']' or lab.emitters[i].name
        end
        local text = {
            Inspect = 'Inspect',
            Emit = 'Burst',
            Enabled = 'Emitting: ' .. (e.enabled and 'ON' or 'OFF'),
            Clear = 'Clear',
            Reset = 'Reset',
            Attraction = 'Attraction: ' .. (e.attractionEnabled and 'ON' or 'OFF'),
            Space = 'Space: ' .. e.simulationSpace,
            Collision = 'Collision: ' .. (e.collisionEnabled and 'ON' or 'OFF'),
            Unlit = 'Unlit: ' .. (e.lightInfluence <= 0 and 'ON' or 'OFF'),
            Blend = 'Blend: ' .. e.blendMode,
            ['Move support'] = 'Move emitter +10 X',
        }
        for key, b in pairs(lab.buttons) do
            b.text = text[key]
        end
    end
    for _, item in pairs(lab.sliders) do
        item.node.value = item.get()
        item.label.text = string.format('%s: %.2f', item.text, item.get())
    end
    local s = lab.scene.world.particles.stats
    lab.status.text = string.format(
        '%s | %d live / %d total\nDropped %d | rays %d/%d\nCPU %.2f ms | %d draws',
        e.name,
        e.liveCount,
        s.live,
        s.dropped,
        s.collisionQueries,
        lab.scene.world.particles.collisionBudget,
        s.updateMilliseconds or 0,
        s.drawCalls or 0
    )
end

return Controls

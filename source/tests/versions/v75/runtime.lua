local T = {}
T.__index = T

function T.new(manager)
    return setmetatable({ manager = manager, count = 0 }, T)
end

function T:check(ok, message)
    assert(ok, message)
    self.count = self.count + 1
    print('PASS v75 ' .. message)
end

function T:update() end

function T:draw()
    if self.done then
        return
    end
    self.done = true
    love.window.setMode(640, 360, { vsync = 0, depth = 24, stencil = 8 })
    local s = self.manager:switch(require('source.game.runtime.game').new, 'combined')
    local r, w, c = s.renderer, s.world, s.camera
    w.environment.shadows.enabled, w.environment.gizmos.enabled = false, false
    w.environment.render.frameCache = false
    local time = 1

    local function draw()
        r:draw(w, c, time, true)
    end
    draw()
    draw()
    self:check(
        r.batches.comparisons == 0 and r.batches.matrixRows == 0,
        'Unchanged instances reuse material membership and matrix rows'
    )

    local function identical(label)
        local a = r.canvas:newImageData()
        r:invalidate()
        draw()
        local b = r.canvas:newImageData()
        self:check(a:getString() == b:getString(), label)
        a:release()
        b:release()
    end
    local cube = w.byName['Cube10.2']
    cube.rotation[2] = 37
    draw()
    self:check(r.batches.matrixRows == 1, 'One moving cube rewrites one instance matrix')
    local uploaded = 0
    for _, g in ipairs(r.batches.groups) do
        uploaded = uploaded + (g.uploadedRows or 0)
    end
    self:check(
        uploaded == 1,
        'One moving cube uploads one row instead of the whole instance buffer'
    )
    identical('Moving cube matches full rebuild pixel for pixel')
    local group
    for _, g in ipairs(r.batches.groups) do
        if g.count > 10 then
            group = g
            break
        end
    end
    local representative = assert(group).example
    local surface = representative.children[1]
    local oldColor = surface.color[1]
    surface.color[1] = 0.79
    draw()
    identical('Changing a group representative rebuilds incompatible membership')
    surface.color[1] = oldColor
    draw()
    local hidden = group.members[math.min(4, #group.members)] or cube
    hidden.visible = false
    draw()
    identical('Removing a visible instance shifts rows correctly')
    hidden.visible = true
    draw()
    identical('Returning instances restore the correct transforms')
    local first = r.opaque[1]
    local oldPalette = first._lightPalette
    first._lightPalette = { 123, 456 }
    r.batches:prepare(r.opaque, { meshSnapshots = true })
    local membership = r.batches.membership[first]
    local found
    for i, member in ipairs(membership.group.members) do
        if member == first then
            found = membership.group.data[i]
        end
    end
    self:check(
        found[26] == 123 and found[27] == 456,
        'Light masks refresh independently of unchanged matrices'
    )
    first._lightPalette = oldPalette
    local Lights = require('source.engine.world.lights')
    local a, b = Lights.new(), Lights.new()
    a:update(w, c, r.visible, 10)
    b:update(w, c, r.visible, 10)
    self:check(
        a.count > 0 and a.position[1][4] == b.position[1][4],
        'Separate renderers initialize their own light arrays'
    )
    local selected = a.selected[1]
    local before = a.color[1][4]
    selected.brightness = before + 1
    b:update(w, c, r.visible, 11)
    a:update(w, c, r.visible, 11)
    if a.color[1][4] == before then
        a:update(w, c, r.visible, 12)
    end
    self:check(
        a.color[1][4] == before + 1,
        'Another renderer cannot hide pending light input changes'
    )
    local ui = s.ui
    local scroll =
        ui:scroll({ position = { 0, 0, 0, 0 }, size = { 0, 100, 0, 50 }, length = 300 }, ui.content)
    local child =
        ui:text({ position = { 0, 0, 0, 80 }, size = { 0, 80, 0, 25 }, text = 'Last' }, scroll)
    ui:layout()
    scroll.automaticLength = true
    scroll.contentPadding = 7
    ui:layout()
    self:check(scroll.length == 112, 'Automatic length and padding edits invalidate layout')
    local snapshot = scroll._lengthSnapshot
    scroll.scrollY = 20
    ui:layout()
    self:check(
        scroll.length == 112 and scroll._lengthSnapshot == snapshot,
        'Scrolling reuses the extent snapshot without changing content length'
    )
    child.visible = false
    ui:layout()
    self:check(
        scroll.length == 7 and scroll.scrollY == 0,
        'Hidden content shrinks automatic length and clamps scroll'
    )
    child.visible, child.textScaled = true, true
    ui:draw()
    self:check(not child._textDrawables, 'Fully clipped scaled labels skip glyph preparation')
    scroll:destroy()
    -- Compare retained glyph geometry with the original print/printf operations,
    -- under the same transforms, clipping, outlines and rich text styles.
    local Text = require('source.engine.ui.drawing.text')
    local g = love.graphics
    local label = ui:text({
        position = { 0, 8, 0, 8 },
        size = { 0, 230, 0, 90 },
        text = 'AVATAR fi Hello \226\156\147\nwrap words',
        fontSize = 19,
    }, ui.content)
    local outline = ui:create(
        'UIStroke',
        { target = 'Text', thickness = { 0, 2 }, color = { 0.4, 0.7, 1 } },
        label
    )
    ui:layout()

    local function capture(reference)
        local target = g.newCanvas(640, 360)
        g.push('all')
        g.setCanvas({ target, stencil = true })
        g.origin()
        g.clear(0, 0, 0, 0)
        local original = g.draw
        if reference then
            local lookup = {}
            for _, line in ipairs(label._textLines or {}) do
                for _, run in ipairs(line.runs) do
                    lookup[run.drawable] = run
                end
            end
            g.draw = function(object, x, y, ...)
                if label._textDrawables.mode == 'fixed' and object == label._textDrawables[1] then
                    g.printf(label.text, x, y, label._wrapWidth, label.align or 'center')
                elseif lookup[object] then
                    g.print(lookup[object].text, x, y)
                else
                    original(object, x, y, ...)
                end
            end
        end
        Text.drawLabel(ui, label)
        g.draw = original
        g.pop()
        local data = target:newImageData()
        target:release()
        return data
    end
    for _, mode in ipairs({ 'left', 'center', 'right', 'justify', 'rich', 'scaled' }) do
        label.richText, label.textScaled = mode == 'rich', mode == 'scaled'
        label.align = (mode == 'rich' or mode == 'scaled') and 'left' or mode
        if mode == 'rich' then
            label.text = '<b>Bold</b> <i>Italic</i> <u>Line</u> Hello \226\156\147'
        end
        local candidate = capture(false)
        local reference = capture(true)
        self:check(
            candidate:getString() == reference:getString(),
            'Retained text matches original drawing: ' .. mode
        )
        candidate:release()
        reference:release()
    end
    local resources = label._textDrawables
    label:destroy()
    self:check(#resources == 0, 'Destroying text releases its retained glyph resources')
    print('PASSED ' .. self.count .. ' focused v75 checks')
    love.event.quit()
end

return T

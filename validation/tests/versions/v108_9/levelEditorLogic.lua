-- Level editor pure logic: the ZIP writer against the engine's own reader, the location format,
-- the snap and drag math and the undo stack. None of it needs a window.
local Archive = require('source.katsa.core.archive')
local Crc32 = require('game.scenes.levelEditor.scripts.io.crc32')
local Format = require('game.scenes.levelEditor.scripts.io.locationFormat')
local LuaText = require('game.scenes.levelEditor.scripts.io.luaText')
local Bounds = require('game.scenes.levelEditor.scripts.core.bounds')
local Selection = require('game.scenes.levelEditor.scripts.core.selection')
local Snap = require('game.scenes.levelEditor.scripts.core.snap')
local Undo = require('game.scenes.levelEditor.scripts.core.undo')
local ZipWriter = require('game.scenes.levelEditor.scripts.io.zipWriter')

local Module = {}

local function near(a, b)
    return math.abs(a - b) < 1e-6
end

function Module.zip(self)
    self:check(Crc32.of('123456789') == 0xCBF43926, 'CRC-32 matches the standard check value')
    local zip = ZipWriter.new()
    zip:add('settings.lua', 'return {}\n')
    zip:addDirectory('assets/models')
    zip:add('assets/textures/a.bin', string.char(0, 1, 2, 255, 254))
    zip:add('assets/ünï.txt', 'utf8 name')
    local text = zip:build()
    local archive = Archive.fromString(text, 'written')
    self:check(archive:read('settings.lua') == 'return {}\n', 'The engine reader reads a stored entry')
    self:check(
        archive:read('assets/textures/a.bin') == string.char(0, 1, 2, 255, 254),
        'Binary bytes survive the ZIP writer'
    )
    self:check(archive:read('assets/ünï.txt') == 'utf8 name', 'UTF-8 entry names are kept')
    self:check(
        archive:info('assets/models') and archive:info('assets/models').type == 'directory',
        'An explicit directory entry is listed as a directory'
    )
    self:check(ZipWriter.new():add('a', 'x'):build() == ZipWriter.new():add('a', 'x'):build(), 'The archive bytes are deterministic')
    self:check(not pcall(function() zip:add('settings.lua', '') end), 'A duplicate entry name is refused')
end

function Module.format(self)
    local tree = {
        { class = 'Node3D', name = 'Group', properties = { position = { 1, 2.5, -3 } }, children = {
            { class = 'Mesh3D', name = 'Floor', properties = { kind = 'cube', color = { 1, 0.5, 0.25, 1 }, visible = true }, children = {} },
        } },
    }
    local adapter = {
        className = function(n) return n.class end,
        name = function(n) return n.name end,
        properties = function(n) return n.properties end,
        children = function(n) return n.children end,
    }
    local data = Format.encode(tree, adapter)
    local text = LuaText.serialize(data)
    self:check(text == LuaText.serialize(Format.encode(tree, adapter)), 'Serializing twice gives the same text')
    local parsed, problem = Format.parse(text)
    self:check(parsed ~= nil, 'A written location parses again' .. tostring(problem or ''))
    local seen = {}
    local count = Format.decode(parsed, {
        create = function(class, name, properties, parent)
            seen[#seen + 1] = { class = class, name = name, properties = properties, parent = parent }
            return name
        end,
    })
    self:check(count == 2 and seen[2].parent == 'Group' and seen[2].properties.color[2] == 0.5, 'Export then import rebuilds the tree and its properties')
    self:check(near(seen[1].properties.position[2], 2.5), 'Fractional numbers round-trip exactly')
    local _, message = Format.check({ format = Format.NAME, version = 99, nodes = {} })
    self:check(message and message:find('Unsupported location version 99'), 'An unknown version gives a clear message')
    self:check(Format.parse('return os.exit()') == nil, 'A location file cannot run code')
    local package = Archive.fromString(Format.pack(data, { ['assets/textures/x.png'] = 'png' }, '-- loader\n'), 'package')
    self:check(package:has('settings.lua') and package:has('main.lua') and package:has('assets/location.lua'), 'The package is a scene layout')
    self:check(package:read('assets/textures/x.png') == 'png', 'Copied assets live inside the package')
end

function Module.snap(self)
    self:check(near(Snap.value(1.26, 0.5), 1.5) and Snap.value(1.26, 0) == 1.26, 'Values snap to the step; a zero step leaves them')
    self:check(Snap.angle(190, 15) == -165 and Snap.angle(-180, 15) == 180, 'Angles snap and wrap to (-180, 180]')
    self:check(Snap.active(true, false) and not Snap.active(true, true) and Snap.active(false, true), 'Ctrl inverts snapping')
    -- ray from (3, 5, 0) straight down at the X axis through the origin: closest point is x = 3
    local t = Snap.axisParameter({ 3, 5, 0 }, { 0, -1, 0 }, { 0, 0, 0 }, { 1, 0, 0 })
    self:check(near(t, 3), 'A drag along an axis reads the closest point on that axis')
    self:check(Snap.axisParameter({ 0, 1, 0 }, { 1, 0, 0 }, { 0, 0, 0 }, { 1, 0, 0 }) == nil, 'A ray parallel to the axis gives no drag')
    local hit = Snap.planePoint({ 1, 4, 2 }, { 0, -1, 0 }, { 0, 0, 0 }, { 0, 1, 0 })
    self:check(hit and near(hit[1], 1) and near(hit[2], 0) and near(hit[3], 2), 'A plane handle meets the ray on the plane')
    self:check(near(Snap.angleAround({ 0, 1, 0 }, { 0, 0, 1 }, { 1, 0, 0 }), 90), 'A rotation drag measures a signed angle')
    self:check(near(Snap.scaleFactor(2, 3), 1.5) and Snap.scaleFactor(0, 5) == 1 and Snap.scaleFactor(2, 0) == 0.01, 'Scale factors stay away from zero')
end

function Module.undo(self)
    local value, stack = 0, Undo.new()
    local function set(to, from)
        return { name = 'set', redo = function() value = to end, undo = function() value = from end }
    end
    stack:push(set(1, 0))
    stack:push(set(2, 1))
    self:check(value == 2 and stack:undo() and value == 1 and stack:redo() and value == 2, 'Undo and redo restore the value')
    stack:undo()
    stack:push(set(9, 1))
    self:check(not stack:canRedo(), 'A new change clears the redo list')
    local drag = Undo.new()
    value = 0
    for step = 1, 5 do
        local c = set(step, step - 1)
        c.key = 'drag'
        drag:push(c)
    end
    drag:seal()
    drag:undo()
    self:check(#drag.done == 0 and value == 0, 'A drag with one key is one undo step')
    local grouped = Undo.new()
    value = 0
    grouped:begin('both')
    grouped:push(set(1, 0))
    grouped:push(set(2, 1))
    grouped:commit()
    grouped:undo()
    self:check(value == 0 and #grouped.done == 0, 'A transaction undoes as one step')
end

function Module.selection(self)
    local selection, changes = Selection.new(), 0
    selection:onChange(function() changes = changes + 1 end)
    local a, b = { name = 'a' }, { name = 'b' }
    selection:set({ a })
    selection:toggle(b)
    self:check(selection:count() == 2 and selection:primary() == b, 'The last added item is the primary selection')
    selection:toggle(a)
    selection:add(b)
    self:check(selection:count() == 1 and not selection:has(a) and changes == 3, 'Toggling removes an item and re-adding changes nothing')
    local center, radius = Bounds.sphere({ { position = { 0, 0, 0 }, size = { 2, 2, 2 } }, { position = { 4, 0, 0 }, size = { 2, 2, 2 } } })
    self:check(center[1] == 2 and math.abs(radius - (2 + math.sqrt(3))) < 1e-9 and Bounds.sphere({}) == nil, 'Bounds cover every item and an empty list has none')
end

function Module.run(self)
    Module.selection(self)
    Module.zip(self)
    Module.format(self)
    Module.snap(self)
    Module.undo(self)
end

return Module

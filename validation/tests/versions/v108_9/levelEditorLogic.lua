-- Level editor pure logic: the ZIP writer against the engine's own reader, the location format,
-- the snap and drag math and the undo stack. None of it needs a window.
local Archive = require('source.katsa.core.archive')
local Crc32 = require('game.scenes.levelEditor.scripts.io.crc32')
local Format = require('game.scenes.levelEditor.scripts.io.locationFormat')
local LuaText = require('game.scenes.levelEditor.scripts.io.luaText')
local Bounds = require('game.scenes.levelEditor.scripts.core.bounds')
local GizmoMath = require('game.scenes.levelEditor.scripts.core.gizmoMath')
local AssetStore = require('game.scenes.levelEditor.scripts.io.assetStore')
local Shapes = require('game.scenes.levelEditor.scripts.builders.shapes')
local PackagePaths = require('game.scenes.levelEditor.scripts.io.packagePaths')
local Recent = require('game.scenes.levelEditor.scripts.io.recent')
local EditorSettings = require('game.scenes.levelEditor.scripts.io.editorSettings')
local Pointer = require('game.scenes.levelEditor.scripts.input.pointer')
local TouchLayout = require('game.scenes.levelEditor.scripts.ui.support.touchLayout')
local Assign = require('game.scenes.levelEditor.scripts.core.assign')
local LevelFiles = require('game.scenes.levelEditor.scripts.io.levelFiles')
local Flow = require('game.scenes.levelEditor.scripts.ui.support.flow')
local Layout = require('game.scenes.levelEditor.scripts.ui.support.layout')
local PropertyGroups = require('game.scenes.levelEditor.scripts.ui.support.propertyGroups')
local Shortcut = require('game.scenes.levelEditor.scripts.ui.support.shortcut')
local Builder = require('game.scenes.levelEditor.scripts.view.meshBuilder')
local Selection = require('game.scenes.levelEditor.scripts.core.selection')
local Snap = require('game.scenes.levelEditor.scripts.core.snap')
local TreeModel = require('game.scenes.levelEditor.scripts.core.treeModel')
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

function Module.tree(self)
    local root = { name = 'root' }
    local a, b, c = { name = 'a', parent = root }, { name = 'b', parent = root }, { name = 'c' }
    c.parent = a
    root.children, a.children, b.children, c.children = { a, b }, { c }, {}, {}
    local function childrenOf(n) return n.children end
    local function parentOf(n) return n.parent end
    local rows = TreeModel.flatten(root, childrenOf, { [root] = true })
    self:check(#rows == 3 and rows[2].node == a and rows[2].hasChildren and not rows[2].expanded, 'A collapsed branch hides its children')
    rows = TreeModel.flatten(root, childrenOf, { [root] = true, [a] = true }, rows)
    self:check(#rows == 4 and rows[3].node == c and rows[3].depth == 2, 'An expanded branch lists its children one level deeper')
    self:check(not TreeModel.canReparent(a, c, parentOf) and not TreeModel.canReparent(a, a, parentOf) and TreeModel.canReparent(c, b, parentOf), 'A node cannot move into itself or its own descendant')
    local top = TreeModel.topLevel({ a, c, b }, parentOf)
    self:check(#top == 2 and top[1] == a and top[2] == b, 'Moving a group already carries its selected children')
    local range = TreeModel.range(rows, a, b)
    self:check(range and #range == 3 and range[1] == a and range[3] == b, 'A range selects the rows between two nodes')
    local span = TreeModel.slice(rows, 4, 1, root)
    self:check(#span == 3 and span[1] == a and span[3] == b, 'Dragging over rows selects them in either direction, without the root')
    self:check(#TreeModel.slice(rows, 3, 99, root) == 2, 'A drag past the last row is clamped to the list')
end

-- The engine's euler convention (math3d.compose, Affine.euler), restated for the pure test.
local function compose(_, r)
    local x, y, z = math.rad(r[1]), math.rad(r[2]), math.rad(r[3])
    local cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    return {
        cz * cy, -cz * sy * sx - sz * cx, -cz * sy * cx + sz * sx, 0,
        sz * cy, -sz * sy * sx + cz * cx, -sz * sy * cx - cz * sx, 0,
        sy, cy * sx, cy * cx, 0,
        0, 0, 0, 1,
    }
end

local function euler(m)
    local y = math.asin(math.max(-1, math.min(1, m[9])))
    local x, z = math.atan2 and math.atan2(m[10], m[11]) or math.atan(m[10], m[11]), nil
    z = math.atan2 and math.atan2(m[5], m[1]) or math.atan(m[5], m[1])
    return { math.deg(x), math.deg(y), math.deg(z) }
end

function Module.gizmo(self)
    local axes = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
    local pivot = { 0, 0, 0 }
    -- a camera 10 units in front looking down -Z at the pivot
    local function ray(x, y)
        local length = math.sqrt(x * x + y * y + 100)
        return { { x, y, 10 }, { 0, 0, -1 } }, length
    end
    local r = ray(0.6, 0)
    self:check(GizmoMath.pick('Move', r, pivot, axes, 1, 0.1) == 'x', 'A ray near the X arrow picks the X handle')
    self:check(GizmoMath.pick('Move', ray(0, 0.7), pivot, axes, 1, 0.1) == 'y', 'A ray near the Y arrow picks the Y handle')
    self:check(GizmoMath.pick('Move', ray(0.9, 0.9), pivot, axes, 1, 0.1) == nil, 'A ray far from every handle picks nothing')
    self:check(GizmoMath.pick('Move', ray(0.35, 0.35), pivot, axes, 1, 0.1) == 'xy', 'A ray through the plane square picks the plane handle')
    self:check(GizmoMath.pick('Rotate', ray(0, 0), pivot, axes, 1, 0.1) == nil, 'The middle of a rotation ring picks nothing')
    local through = { { 0, 0, 10 }, { 0, 0, -1 } }
    self:check(GizmoMath.pick('Rotate', { { 1, 0, 10 }, { 0, 0, -1 } }, pivot, axes, 1, 0.1) == 'z', 'A ray through the Z ring picks it')
    self:check(GizmoMath.pick('Scale', through, pivot, axes, 1, 0.1) == 'all', 'The centre of the scale gizmo is the uniform handle')
    local m = GizmoMath.axisAngle({ 0, 1, 0 }, 90)
    local p = GizmoMath.rotatePoint({ 1, 0, 0 }, pivot, { 0, 1, 0 }, 90)
    self:check(math.abs(p[3] + 1) < 1e-9 and math.abs(p[1]) < 1e-9 and math.abs(m[15]) < 1e-9, 'A point turns about the world Y axis')
    local turned = GizmoMath.rotateEuler({ 0, 0, 0 }, { 0, 0, 1 }, 30, false, compose, euler)
    self:check(math.abs(turned[3] - 30) < 1e-6 and math.abs(turned[1]) < 1e-6, 'Turning a node about world Z changes its Z rotation')
    local local_ = GizmoMath.rotateEuler({ 0, 0, 40 }, { 1, 0, 0 }, 25, true, compose, euler)
    local world = GizmoMath.rotateEuler({ 0, 0, 40 }, { 1, 0, 0 }, 25, false, compose, euler)
    self:check(math.abs(local_[1] - world[1]) > 1 or math.abs(local_[3] - world[3]) > 1, 'Local and world turns differ for a rotated node')
end

function Module.builder(self)
    local vertices = {}
    Builder.bar(vertices, { 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 }, 0.1)
    self:check(#vertices == 6 * 6 * 2 and #vertices[1] == 8, 'A bar has six double-sided faces of engine vertices')
    local ring = {}
    Builder.ring(ring, 2, 1, 0.01, 12)
    local far = 0
    for _, v in ipairs(ring) do
        far = math.max(far, math.abs(v[2]))
    end
    self:check(#ring == 12 * #vertices and far < 0.05, 'A ring around Y stays in the XZ plane')
end

function Module.shapes(self)
    for _, name in ipairs(Shapes.NAMES) do
        local list = Shapes.vertices(name)
        local outward = true
        for i = 1, #list, 3 do
            local a, b, c = list[i], list[i + 1], list[i + 2]
            local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
            local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
            local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
            local dot = nx * a[6] + ny * a[7] + nz * a[8]
            outward = outward and dot > 0
        end
        self:check(#list % 3 == 0 and outward, name .. ' triangles wind counter-clockwise around their normals')
    end
end

function Module.assets(self)
    local function never()
        return false
    end
    self:check(AssetStore.kind('a/b/Crate.PNG') == 'image' and AssetStore.kind('x.glb') == 'model' and AssetStore.kind('x.txt') == 'file', 'Asset kinds follow the file extension')
    self:check(AssetStore.targetPath('dir/my crate.glb', 'model', never) == 'editor/assets/models/my_crate.glb', 'Store names are made safe')
    local taken = { ['editor/assets/textures/a.png'] = true, ['editor/assets/textures/a_2.png'] = true }
    self:check(AssetStore.targetPath('a.png', 'image', function(path) return taken[path] end) == 'editor/assets/textures/a_3.png', 'A clashing name gets the next free number')
    self:check(AssetStore.packagePath('editor/assets/models/a.glb') == 'assets/models/a.glb' and AssetStore.storePath('assets/models/a.glb') == 'editor/assets/models/a.glb', 'Store and package paths convert both ways')
end

function Module.package(self)
    local tree = { a = 'editor/assets/models/x.glb', b = { 'editor/assets/textures/t.png', 'keep' }, n = 3 }
    local moved = PackagePaths.rewrite(tree, 'editor/assets/', 'assets/')
    self:check(moved.a == 'assets/models/x.glb' and moved.b[1] == 'assets/textures/t.png' and moved.b[2] == 'keep' and tree.a:sub(1, 6) == 'editor', 'Store paths become package paths without touching the original')
    local used = PackagePaths.collect(tree, 'editor/assets/', {})
    self:check(used['editor/assets/models/x.glb'] and used['editor/assets/textures/t.png'] and not used.keep, 'Asset paths are collected')
    local clean, dropped = PackagePaths.sanitize({ ok = { 1, 2 }, bad = print, nan = 0 / 0, text = 'x' })
    self:check(dropped == 2 and clean.ok[2] == 2 and clean.text == 'x' and clean.bad == nil, 'Unsavable values are dropped and counted')
    local list = Recent.push(Recent.push(Recent.push({}, 'a'), 'b'), 'a')
    self:check(#list == 2 and list[1] == 'a' and list[2] == 'b', 'A recent entry moves to the front without duplicates')
    for index = 1, 12 do
        list = Recent.push(list, 'f' .. index)
    end
    self:check(#list == Recent.LIMIT and list[1] == 'f12' and #Recent.remove(list, 'f12') == Recent.LIMIT - 1, 'The recent list is capped and entries can be removed')
    local data = Format.encode({ { c = 'Mesh3D', n = 'M', a = { EditorShape = 'cone' }, m = 'assets/models/x.glb' } }, {
        className = function(node) return node.c end,
        name = function(node) return node.n end,
        properties = function() return {} end,
        attributes = function(node) return node.a end,
        model = function(node) return node.m end,
        children = function() return {} end,
    })
    local parsed = Format.parse(LuaText.serialize(data))
    self:check(parsed and parsed.nodes[1].attributes.EditorShape == 'cone' and parsed.nodes[1].model == 'assets/models/x.glb', 'Attributes and model files survive the location format')
end

function Module.interface(self)
    for _, size in ipairs({ { 1280, 720 }, { 1024, 600 }, { 800, 500 } }) do
        local r = Layout.compute(size[1], size[2], Layout.DEFAULTS, 36, 24)
        local across = r.left.w + r.splitLeft.w + r.view.w + r.splitRight.w + r.right.w
        self:check(r.view.w >= Layout.MIN_VIEW.width and r.view.h >= Layout.MIN_VIEW.height and across == size[1], ('The viewport keeps its size and the docks fill the window at %dx%d'):format(size[1], size[2]))
    end
    local wide = Layout.compute(1280, 720, { left = 900, right = 900, bottom = 900 }, 36, 24)
    self:check(wide.view.w >= Layout.MIN_VIEW.width and wide.bottom.y >= wide.view.y + Layout.MIN_VIEW.height, 'Oversized splitter values are clamped')
    local items = {}
    for index = 1, 9 do
        items[index] = { w = 60 }
    end
    local positions, height = Flow.place(items, 300, 4, 26, 5)
    local inside = true
    for index, at in ipairs(positions) do
        inside = inside and at.x + items[index].w <= 300 - 5
    end
    self:check(inside and height > 26 * 2 and positions[1].y == 5, 'Flow wraps items so none leaves the available width')
    local single = Flow.place({ { w = 50 }, { w = 50, row = true } }, 500, 4, 26, 0)
    self:check(single[2].y == 30 and single[2].x == 0, 'Flow starts a new row on request')
    local merged = EditorSettings.merge({ theme = 5, snap = { move = 2, junk = 1 }, other = true })
    self:check(merged.theme == 'dark' and merged.snap.move == 2 and merged.snap.junk == nil and merged.other == nil and merged.layout.left == 250, 'Settings keep known keys of the right type and default the rest')
    local again = EditorSettings.parse(EditorSettings.serialize(merged))
    self:check(again.snap.move == 2 and again.theme == 'dark', 'Settings survive a save and load')
end

function Module.menus(self)
    self:check(Shortcut.format('key:lctrl+key:s') == 'Ctrl+S' and Shortcut.format('key:delete') == 'Del' and Shortcut.format('key:f5') == 'F5', 'Bindings read as shortcut text')
    local rows = {}
    for index, key in ipairs({ 'maxDistance', 'position', 'color', 'visible', 'brightness', 'mystery', 'size' }) do
        rows[index] = { key = key }
    end
    local groups = PropertyGroups.group(rows)
    local names = {}
    for index, group in ipairs(groups) do
        names[index] = group.name
    end
    self:check(table.concat(names, ',') == 'Transform,Appearance,Light,Node,Rendering,Other', 'Inspector rows are grouped in a fixed category order')
    self:check(groups[1].rows[1].key == 'position' and groups[1].rows[2].key == 'size', 'Rows keep their order inside a group')
    self:check(PropertyGroups.COLLAPSED.Rendering and not PropertyGroups.COLLAPSED.Transform and PropertyGroups.of('maxDistance') == 'Rendering', 'maxDistance sits in the collapsed Rendering group')
end

-- A tiny in-memory file system with the calls LevelFiles uses.
local function fakeFs()
    local files, dirs = {}, { [''] = true }
    local fs = {}
    function fs.createDirectory(path)
        dirs[path] = true
        return true
    end
    function fs.getInfo(path, filter)
        if dirs[path] and filter ~= 'file' then
            return { type = 'directory' }
        end
        if files[path] and filter ~= 'directory' then
            return { type = 'file' }
        end
    end
    function fs.read(path)
        return files[path]
    end
    function fs.write(path, data)
        files[path] = data
        return true
    end
    function fs.getDirectoryItems(path)
        local names = {}
        local function scan(set)
            for key in pairs(set) do
                local parent, name = key:match('^(.*)/([^/]+)$')
                if parent == path and name then
                    names[#names + 1] = name
                end
            end
        end
        scan(files)
        scan(dirs)
        table.sort(names)
        return names
    end
    function fs.remove(path)
        files[path], dirs[path] = nil, nil
        return true
    end
    function fs.rename(a, b)
        files[b], files[a] = files[a], nil
        if dirs[a] then
            dirs[b], dirs[a] = true, nil
        end
        return true
    end
    return fs
end

function Module.levelFiles(self)
    local fs = fakeFs()
    self:check(LevelFiles.createFolder('', 'models', fs) == 'models' and LevelFiles.createFile('models', 'a.txt', fs) == 'models/a.txt', 'A folder and a file are created inside the level assets')
    self:check(LevelFiles.createFile('models', 'a.txt', fs) == nil and LevelFiles.createFolder('', '../x', fs) == nil, 'Existing names and path tricks are refused')
    self:check(LevelFiles.clean('a/../b') == nil and LevelFiles.clean('/a//b/') == 'a/b', 'Paths cannot leave the assets folder')
    self:check(LevelFiles.rename('models/a.txt', 'b.txt', fs) == 'models/b.txt' and #LevelFiles.list('models', fs).files == 1, 'A file is renamed in place')
    LevelFiles.createFile('models', 'c.txt', fs)
    self:check(LevelFiles.rename('models/c.txt', 'b.txt', fs) == nil, 'Renaming onto an existing file is refused')
    self:check(LevelFiles.delete('models', fs) and #LevelFiles.list('', fs).dirs == 0 and not LevelFiles.delete('', fs), 'A folder is deleted with its files, the root never')
    local sourceFs = fakeFs()
    sourceFs.write('level/a.png', 'one')
    local first = LevelFiles.importFile('level/a.png', 'textures', sourceFs)
    sourceFs.write(LevelFiles.full('textures/a.png'), 'other')
    local second = LevelFiles.importFile('level/a.png', 'textures', sourceFs)
    local third = LevelFiles.importFile('level/a.png', 'textures', sourceFs)
    self:check(first == 'textures/a.png' and second == 'textures/a_2.png' and third == second, 'An import gets a free name, and the same file is not copied twice')
    self:check(LevelFiles.importFile('level/a.png', '../x', sourceFs) == nil and LevelFiles.folderFor('model') == 'models' and LevelFiles.folderFor('xyz') == 'files', 'Imports stay inside the assets folder and default to a folder by type')
    local diskPath = os.tmpname()
    local disk = io.open(diskPath, 'wb')
    disk:write('png-bytes')
    disk:close()
    local diskFs = fakeFs()
    local fromDisk = LevelFiles.importFile(diskPath, 'textures', diskFs)
    os.remove(diskPath)
    self:check(fromDisk ~= nil and diskFs.read(LevelFiles.full(fromDisk)) == 'png-bytes', 'A file outside the virtual file system (an absolute path from the file dialog) imports')
    local node = { position = { 1, 2, 3 } }
    self:check(not Assign.vec(node, 'position', 1, 2, 3) and Assign.vec(node, 'position', 1, 2, 4) and node.position[3] == 4, 'Per-frame writes only happen when a value changed')
end

function Module.touch(self)
    local controls = TouchLayout.merge({ up = { x = 5, size = 9999 }, bogus = {}, down = { y = 'x' } })
    self:check(controls.up.x == 1 and controls.up.size == TouchLayout.MAX_SIZE and controls.bogus == nil and controls.down.y == TouchLayout.defaults().down.y, 'Touch layouts are clamped and unknown values dropped')
    local cx, cy, r = TouchLayout.circle({ x = 0, y = 1, size = 100 }, 800, 400)
    self:check(cx == 50 and cy == 350 and r == 50, 'A control stays fully inside the viewport')
    self:check(TouchLayout.hit(TouchLayout.defaults(), 800, 400, 0.13 * 800, 0.74 * 400) == 'moveStick' and TouchLayout.hit(TouchLayout.defaults(), 800, 400, 400, 200) == nil, 'A touch finds the control under it')
    local ax, ay = TouchLayout.axes({ x = 0.5, y = 0.5, size = 100 }, 800, 400, 500, 150)
    self:check(ax > 0.8 and ay > 0.4 and math.abs(ax * ax + ay * ay - 1) < 1e-6, 'A stick reads right and up as positive, limited to length 1')
    local ox, oy = TouchLayout.axes({ x = 0.5, y = 0.5, size = 100 }, 800, 400, 402, 201)
    self:check(ox == 0 and oy == 0, 'A stick has a dead zone')
    local moved = { x = 0.5, y = 0.5, size = 100 }
    TouchLayout.moveTo(moved, 800, 400, -50, 9999)
    TouchLayout.resize(moved, -999)
    self:check(moved.x == 50 / 800 and moved.y == 350 / 400 and moved.size == TouchLayout.MIN_SIZE, 'Moving and resizing keep a control in range')
    Pointer.begin(7, 10, 20)
    self:check(Pointer.getX() == 10 and Pointer.isDown(1) and not Pointer.isDown(2), 'A finger acts as the left button')
    local fired = Pointer.update(0.3) or Pointer.update(0.3)
    self:check(fired and Pointer.isDown(2), 'A long press is a right click')
    Pointer.update(0.016)
    Pointer.update(0.016)
    self:check(not Pointer.isDown(2), 'The right click lasts only a moment')
    Pointer.finish()
    Pointer.begin(8, 0, 0)
    Pointer.move(100, 100, 100, 100)
    self:check(not Pointer.update(1) and not Pointer.isDown(2), 'A drag is not a long press')
    Pointer.reset()
    self:check(EditorSettings.defaults().touch.mode == 'auto' and EditorSettings.defaults().touch.controls.moveStick ~= nil, 'Touch settings have defaults')
end

function Module.run(self)
    Module.touch(self)
    Module.levelFiles(self)
    Module.menus(self)
    Module.interface(self)
    Module.package(self)
    Module.shapes(self)
    Module.assets(self)
    Module.builder(self)
    Module.gizmo(self)
    Module.tree(self)
    Module.selection(self)
    Module.zip(self)
    Module.format(self)
    Module.snap(self)
    Module.undo(self)
end

return Module

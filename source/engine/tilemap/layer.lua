-- One layer of a TileMap: sparse cells (x, y integers, y grows downward like the image rows).
-- Cells hold tile ids; a cell is empty when absent. `revision` changes with every edit so
-- caches (colliders, drawing bounds) know when to refresh.
local Layer = {}
Layer.__index = Layer

local OFFSET = 32768

local function key(x, y)
    return (y + OFFSET) * 65536 + (x + OFFSET)
end

local function unkey(k)
    return k % 65536 - OFFSET, math.floor(k / 65536) - OFFSET
end

function Layer.new(name)
    return setmetatable({
        name = name,
        cells = {},
        count = 0,
        revision = 0,
        visible = true,
    }, Layer)
end

function Layer:get(x, y)
    return self.cells[key(x, y)]
end

function Layer:set(x, y, id)
    assert(
        math.abs(x) < OFFSET and math.abs(y) < OFFSET,
        'Tile cell outside +-32767: ' .. x .. ', ' .. y
    )
    local k = key(x, y)
    local old = self.cells[k]
    if old == id then
        return false
    end
    if old == nil then
        self.count = self.count + 1
    elseif id == nil then
        self.count = self.count - 1
    end
    self.cells[k] = id
    self.revision = self.revision + 1
    return true
end

function Layer:clear()
    self.cells, self.count = {}, 0
    self.revision = self.revision + 1
end

-- Calls fn(x, y, id) for every used cell (unspecified order).
function Layer:each(fn)
    for k, id in pairs(self.cells) do
        local x, y = unkey(k)
        fn(x, y, id)
    end
end

-- Smallest rectangle holding every cell: x0, y0, x1, y1 (inclusive) or nil when empty.
function Layer:bounds()
    if self.count == 0 then
        return nil
    end
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for k in pairs(self.cells) do
        local x, y = unkey(k)
        x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
    end
    return x0, y0, x1, y1
end

return Layer

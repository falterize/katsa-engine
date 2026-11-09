local ipairs = require('source.engine.math.array').ipairs
-- The lab owns one TileMap (screen space) painted with the mouse or touch.
local Content = {}
Content.__index = Content

Content.COLUMNS, Content.ROWS, Content.CELL = 30, 15, 32

function Content.new(scene)
    scene.ui.layoutMode = 'Viewport'
    scene.showStats = false
    scene.camera.position = { 0, 30, -80 }
    scene.world.environment.debug.gizmos.enabled = false
    return setmetatable({ scene = scene, brush = 'ground', overlay = {}, snapshot = nil }, Content)
end

-- Paints the cell with the current brush. Ground is a terrain (autotile); other tiles are
-- plain ids, and the non-solid ones go to the Decor layer so they can sit in front of ground.
function Content:paint(x, y, erase)
    local map = self.map
    if x < 0 or y < 0 or x >= Content.COLUMNS or y >= Content.ROWS then
        return
    end
    if erase then
        map:setTerrain(x, y, nil, 'Ground')
        map:eraseCell(x, y, 'Decor')
    elseif self.brush == 'ground' then
        map:setTerrain(x, y, 'ground', 'Ground')
    else
        local id = self.brush
        local solid = id == 17 or id == 18
        map:setCell(x, y, id, solid and 'Ground' or 'Decor')
    end
    self:refreshOverlay()
end

-- Shows the merged collision rectangles of the Ground layer (what buildColliders would create).
function Content:refreshOverlay()
    for _, frame in ipairs(self.overlay) do
        frame:destroy()
    end
    self.overlay = {}
    if not self.showColliders then
        self.rectCount = nil
        return
    end
    local cell = Content.CELL
    local rects = self.map:solidRects('Ground')
    self.rectCount = #rects
    for _, rect in ipairs(rects) do
        self.overlay[#self.overlay + 1] = self.scene.ui:create('Frame', {
            position = { 0, rect.x * cell, 0, rect.y * cell },
            size = { 0, rect.w * cell, 0, rect.h * cell },
            backgroundColor = { 1, 0.2, 0.2 },
            backgroundTransparency = 0.65,
            interactable = false,
        }, self.map)
    end
end

function Content:update(dt)
    self.scene.world:updateNodes(dt)
end

return Content

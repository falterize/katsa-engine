-- Native multi-viewport, UI migration, inspector and planar sizing regressions.
local Runtime = {}
Runtime.__index = Runtime
local zones = {
    'original',
    'models',
    'objects',
    'lights',
    'combined',
    'lights32',
    'physics',
    'collisionModels',
    'flyingAudio',
    'nightPlayer',
    'shadows',
    'nodes',
    'collisionBox',
    'surfaceGallery',
    'uiGallery',
    'audioNodes',
}
local sizes = { { 640, 360 }, { 800, 360 }, { 1280, 720 }, { 1600, 900 }, { 640, 960 } }

function Runtime.new(manager, inspectorOnly, phoneWidths)
    if phoneWidths and #sizes == 5 then
        sizes[#sizes + 1] = { 360, 640 }
        sizes[#sizes + 1] = { 320, 480 }
    end
    return setmetatable({
        manager = manager,
        frame = 0,
        index = inspectorOnly and 20 or 0,
        count = 0,
        limit = inspectorOnly and 21 or #zones * #sizes,
    }, Runtime)
end

function Runtime:check(ok, msg)
    assert(ok, msg)
    self.count = self.count + 1
    print('PASS ' .. msg)
end

function Runtime:update()
    if self.wsToClose then
        self.wsToClose:toggle(false)
        self.wsToClose:update(0.3)
        self.wsToClose = nil
    end
    self.frame = self.frame + 1
    if self.frame % 3 == 1 then
        self.index = self.index + 1
        if self.index > self.limit then
            print('PASSED ' .. self.count .. ' native v48 assertions')
            love.event.quit()
            return
        end
        local zone = zones[(self.index - 1) % #zones + 1]
        local size = sizes[math.floor((self.index - 1) / #zones) + 1]
        love.window.setMode(
            size[1],
            size[2],
            { resizable = true, depth = 24, stencil = 8, highdpi = true, vsync = 0 }
        )
        self.scene = self.manager:switch(require('source.game.runtime.game').new, zone)
    elseif self.frame % 3 == 0 then
        local scene = self.scene
        local ui = scene.ui
        ui:layout()

        local function walk(list)
            for _, node in ipairs(list) do
                assert(
                    #node.size == 4 and #node.position == 4,
                    'UI node lacks UDim2: ' .. node.className
                )
                assert(node._width >= 0 and node._height >= 0, 'Negative layout')
                walk(node.children)
            end
        end
        walk(ui.children)
        for _, board in ipairs(scene.world.billboards) do
            assert(
                #board.size == 4 and #board.position == (board:isA('SurfaceUI') and 4 or 3),
                'World3D UI root migration'
            )
            board.ui:layout()
            walk(board.children)
        end
        self:check(
            ui.scale == 1 and ui.width == love.graphics.getWidth(),
            'Viewport / UDim2 ' .. scene.zone .. ' ' .. ui.width .. 'x' .. ui.height
        )
        self:check(
            scene.renderer.actualMSAA == 0 and scene.renderer.renderDensity == 1,
            'Mobile default quality ' .. scene.zone
        )
        local ws = scene.workspace
        ws:toggle(true)
        ws:update(0.3)
        ui:layout()
        ws:renderRows()
        self:check(
            ws.panel._x >= 0
                and ws.panel._x + ws.panel._width <= ui.width + 0.01
                and ws.panel._height <= ui.height,
            'Inspector fits viewport ' .. scene.zone
        )
        self:check(
            #ws.rowPool <= math.ceil(ui.height / 34) + 2,
            'Inspector row virtualization ' .. scene.zone
        )
        if scene.zone == 'combined' then
            ws:beginSearch()
            ws:textinput('Cube')
            ws:commit()
            self:check(
                #ws.rows > 0 and #ws.rowPool < 100,
                'Search keeps ancestry with bounded UI allocation'
            )
        end
        if scene.zone == 'surfaceGallery' then
            local decal = scene.demo.litter
            local before = decal.worldWidth
            decal.size = { 0.4, 0, 0.4, 0 }
            decal:update(scene.world, scene.camera)
            self:check(
                math.abs(decal.worldWidth / before - 0.4 / 0.75) < 0.001,
                'Decal3D Size changes world coverage'
            )
            local fields = require('source.engine.editor.inspectors.properties').list(decal)
            for _, field in ipairs(fields) do
                assert(
                    field.key ~= 'scale' and field.key ~= 'surfaceSize',
                    'Duplicate surface dimensions in inspector'
                )
            end
        end
        if scene.zone == 'uiGallery' then
            ws:select(scene.demo.button)
            local fields =
                require('source.engine.editor.inspectors.properties').list(scene.demo.button)
            for _, field in ipairs(fields) do
                assert(not ({
                    width = true,
                    height = true,
                    x = true,
                    y = true,
                    scale = true,
                    color = true,
                })[field.key], 'Legacy UI inspector field')
            end
            self:check(#scene.demo.button.position == 4, 'Inspector UI coordinate schema')
        end
        if self.index == 15 or self.index == 16 or self.index == 21 or self.index == 46 then
            love.graphics.captureScreenshot(function(img)
                img:encode(
                    'png',
                    'v48-' .. scene.zone .. '-' .. ui.width .. 'x' .. ui.height .. '.png'
                )
                img:release()
            end)
        end
        if self.index == 21 then
            ws:select(scene.world.objects[2])
            self.wsShot = true
            self.wsToClose = ws
        else
            ws:toggle(false)
            ws:update(0.3)
        end
    end
end

function Runtime:draw()
    if self.wsShot then
        self.wsShot = nil
        love.graphics.captureScreenshot(function(img)
            img:encode('png', 'v48-workspace-800x360.png')
            img:release()
        end)
    end
end

return Runtime

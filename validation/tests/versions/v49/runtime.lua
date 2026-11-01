-- Focused native popup/input/property tests, followed by every v48 viewport case.
local Base = require('validation.tests.versions.v48.runtime')

local Runtime = {}
Runtime.__index = Runtime

function Runtime.new(manager)
    return setmetatable(
        { manager = manager, base = Base.new(manager, false, true), checks = 0 },
        Runtime
    )
end

function Runtime:check(ok, message)
    assert(ok, message)
    self.checks = self.checks + 1
    print('PASS v49 ' .. message)
end

function Runtime:update()
    self.base:update()
    if self.base.frame % 3 ~= 0 or not self.base.scene then
        return
    end
    local scene = self.base.scene
    local ws = scene.workspace
    local ui = scene.ui
    if scene.zone == 'uiGallery' then
        ws:toggle(true)
        ws:update(0.3)
        ws:select(scene.demo.button)

        local function field(key)
            for _, f in ipairs(ws.fields) do
                if f.key == key then
                    return f
                end
            end
            error('Missing property ' .. key)
        end
        local f = field('backgroundColor')
        ws:openPopup(f)
        local popup = ws.popup
        ui:layout()
        self:check(
            popup.panel._x >= 0
                and popup.panel._y >= 0
                and popup.panel._x + popup.panel._width <= ui.width,
            'color popup fits viewport'
        )
        local original = { unpack(scene.demo.button.backgroundColor) }
        popup:setRGB({ 1, 0.5, 0 })
        self:check(scene.demo.button.backgroundColor[1] == 1, 'RGB preview updates live UI')
        popup:close(false)
        self:check(
            scene.demo.button.backgroundColor[1] == original[1],
            'Cancel restores original RGB'
        )
        ws:openPopup(f)
        popup = ws.popup
        ui:scrollBy(popup.body, 100000)
        local x, y = ui:position(popup.hex)
        scene.input:press('hex', x + 5, y + 5)
        scene.input:release('hex')
        ws:textinput('#123456')
        ws:commit()
        self:check(
            math.abs(scene.demo.button.backgroundColor[1] - 18 / 255) < 1e-8,
            'touch HEX entry updates normalized RGB'
        )
        popup:close(true)
        ws:openPopup(field('relativeTo'))
        popup = ws.popup
        ui:layout()
        local option = popup.body.children[2]
        x, y = ui:position(option)
        self:check(ui:hit(x + 5, y + 5) == option, 'dropdown is above clipped inspector')
        scene.input:press('enum', x + 5, y + 5)
        scene.input:release('enum')
        self:check(
            scene.demo.button.relativeTo == 'XX' and not ws.popup,
            'touch dropdown selects and closes'
        )
        scene.demo.button.relativeTo = 'XY'
        ws:openPopup(field('size'))
        popup = ws.popup
        local old = scene.demo.button.size[2]
        require('source.engine.editor.inspectors.properties').set(
            scene,
            scene.demo.button,
            field('size'),
            '0',
            2
        )
        ws:keypressed('escape')
        self:check(
            scene.demo.button.size[2] == old and not ws.popup,
            'Escape cancels vector preview'
        )
        ws:openPopup(field('backgroundColor'))
        popup = ws.popup
        scene.input:press('outside', 1, 1)
        scene.input:release('outside')
        self:check(not ws.popup, 'outside touch dismisses popup')
        ui:layout()
        ui:scrollBy(scene.demo.left, 100000)
        self:check(
            scene.demo.left.scrollY == math.max(0, scene.demo.left.length - scene.demo.left._height),
            'UDim2 scroll ends at resolved content limit'
        )
        self:check(
            scene.demo.button.x == nil and scene.demo.button.width == nil,
            'legacy pixel fields are removed after load'
        )
        ws:toggle(false)
        ws:update(0.3)
    end
    if scene.zone == 'audioNodes' then
        local props = require('source.engine.editor.inspectors.properties')
        for _, effect in ipairs(scene.audio.effects) do
            local fields = props.list(effect)
            local has = false
            for _, f in ipairs(fields) do
                if f.key == 'effectType' then
                    has = true
                end
            end
            self:check(has, 'inspector schema for ' .. effect.className)
        end
    end
    if
        self.base.index
        == #{
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
            * 7
    then
        print('PASSED ' .. self.checks .. ' focused v49 native assertions')
    end
end

function Runtime:draw()
    self.base:draw()
end

return Runtime

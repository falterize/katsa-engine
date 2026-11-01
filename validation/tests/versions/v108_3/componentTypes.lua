-- Inspector fields follow the node class: an ImageLabel exposes image fields, not text fields,
-- and describing one class never leaks fields into its base or its siblings.
local Application = require('source.game.runtime.application')
local Schema = require('source.engine.editor.inspectors.schema')

local Module = {}

local function fieldSet(scene, class)
    local node = scene.ui:create(class, {}, scene.ui.content)
    local set = {}
    for _, key in ipairs(Schema.keys(node, {})) do
        set[key] = true
    end
    node:destroy()
    return set
end

function Module.run(self)
    local scene = Application.new(self.manager, 'models')
    scene:load()
    scene:update(1 / 60, 1 / 60)
    local frame = fieldSet(scene, 'Frame')
    local image = fieldSet(scene, 'ImageLabel')
    local text = fieldSet(scene, 'TextLabel')
    local button = fieldSet(scene, 'Button')
    self:check(
        image.image and image.imageMode and image.pixelate,
        'ImageLabel lists image fields'
    )
    self:check(
        not (image.text or image.fontSize or image.textColor),
        'ImageLabel lists no text fields'
    )
    self:check(text.text and text.fontSize, 'TextLabel lists text fields')
    self:check(
        not (text.image or text.imageMode or text.pixelate),
        'TextLabel lists no image fields'
    )
    self:check(
        not (frame.image or frame.imageMode or frame.pixelate or frame.text),
        'Frame lists neither image nor text fields'
    )
    self:check(button.image and button.text, 'Button lists image and text fields')
    local Properties = require('source.engine.editor.inspectors.properties')
    local label = scene.ui:create('ImageLabel', {}, scene.ui.content)
    local ok, message = Properties.set(scene, label, { key = 'text', kind = 'string' }, 'hello')
    self:check(ok == false and tostring(message):find('no property'), 'ImageLabel rejects text')
    ok = Properties.set(scene, label, { key = 'imageMode', kind = 'string' }, 'Tiles')
    self:check(ok ~= false, 'ImageLabel accepts its own imageMode')
    label:destroy()
end

return Module

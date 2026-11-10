local Objects = require('../../core.objects')
local Array = require('../../math.array')
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
-- Install one cohesive responsibility on the public class.
local Schema = require('./schema')
local fields = require('./propertyPolicy').fields
local PropertyRead = {}

function PropertyRead.install(Properties)
    function Properties.numeric(list)
        for i = 1, #list do
            if type(list[i]) ~= 'number' then
                return false
            end
        end
        return true
    end

    function Properties.parentPath(node)
        local parts = {}
        local parent = node.parent
        while parent do
            table.insert(parts, 1, parent.name or parent.className or 'Node')
            parent = parent.parent
        end
        return #parts > 0 and table.concat(parts, ' / ') or 'nil (root)'
    end

    function Properties.list(target)
        local result = {}
        if target.uniforms and target.shader then
            result[#result + 1] = {
                key = 'kind',
                kind = 'string',
                value = target.kind,
                readOnly = true,
                reason = 'Shader type is fixed at creation.',
            }
            result[#result + 1] = { key = 'animated', kind = 'boolean', value = target.animated }
            for key, value in pairs(target.uniforms) do
                local kind = Array.is(value) and 'table' or Objects.kind(value)
                if
                    kind == 'number'
                    or kind == 'boolean'
                    or kind == 'string'
                    or kind == 'table' and #value >= 2 and #value <= 4
                then
                    result[#result + 1] = {
                        key = key,
                        kind = kind == 'table' and 'vector' or kind,
                        value = value,
                        container = target.uniforms,
                    }
                else
                    result[#result + 1] = {
                        key = key,
                        kind = 'string',
                        value = tostring(value),
                        readOnly = true,
                        reason = 'Use Material:set for this resource or structured uniform.',
                    }
                end
            end
            table.sort(result, function(a, b)
                return a.key < b.key
            end)
            return result
        end
        if target._node then
            result[#result + 1] = {
                key = 'parent',
                kind = 'string',
                value = Properties.parentPath(target),
                readOnly = true,
            }
        end
        for _, key in ipairs(Schema.keys(target, fields)) do
            local reference = require('source.engine.editor.inspectors.nodeReferences').expected(
                target,
                key
            ) ~= nil
            local getter = Schema.descriptor(target, key).get
            local value = getter and getter(target) or target[key]
            if
                reference
                or key == 'currentCamera' and target:isA('World3D')
                or key == 'adornee' and target.setAdornee
                or key == 'positionSource' and target:isA('ClickDetector3D')
                or key == 'adornee' and target:isA('Ramp')
            then
                result[#result + 1] =
                    { key = key, kind = 'node', value = value, hint = Schema.hint(target, key) }
            end
            if target.isA and target:isA('UINode') and not target.modifier then
                local channel = key:match('^(background)Color$')
                    or key:match('^(image)Color$')
                    or key:match('^(text)Color$')
                if channel then
                    local color = require('source.engine.ui.style').color(target, channel)
                    if color then
                        value = { color[1], color[2], color[3] }
                    end
                end
                local alphaChannel = key:match('^(background)Transparency$')
                    or key:match('^(image)Transparency$')
                    or key:match('^(text)Transparency$')
                if alphaChannel and value == nil then
                    local color = require('source.engine.ui.style').color(target, alphaChannel)
                    value = 1 - (color and color[4] or 1)
                end
                if key == 'position' and not value then
                    value = { 0, target.x, 0, target.y }
                end
                if key == 'size' and not value then
                    value = { 0, target.width, 0, target.height }
                end
                if key == 'anchorPoint' and not value then
                    value = { 0, 0 }
                end
                if key == 'relativeTo' and not value then
                    value = 'XY'
                end
                if (key == 'textScaled' or key == 'richText') and value == nil then
                    value = false
                end
            end
            if target.isA and target:isA('UINode') and not target.modifier then
                if
                    ({
                        x = true,
                        y = true,
                        width = true,
                        height = true,
                        scale = true,
                        color = true,
                        tint = true,
                    })[key]
                    or (key == 'transparency' and not target:isA('CanvasGroup'))
                then
                    value = nil
                end
            end
            if
                target.isA
                and (target:isA('Decal3D') or target:isA('BillboardUI'))
                and (key == 'scale' or key == 'surfaceSize' or key == 'screenOffset')
            then
                value = nil
            end
            if key == 'color' and target.isA and target:isA('Mesh3D') and Array.is(value) then
                value = { value[1], value[2], value[3] }
            end
            local kind = Array.is(value) and 'table' or Objects.kind(value)
            local descriptor = Schema.descriptor(target, key)
            if reference then
                kind = 'structured'
            end
            if descriptor.kind and kind == 'table' then
                result[#result + 1] = { key = key, kind = descriptor.kind, value = value }
                kind = 'structured'
            end
            if kind == 'boolean' or kind == 'number' or kind == 'string' then
                result[#result + 1] = {
                    key = key,
                    kind = kind,
                    value = value,
                    hint = Schema.hint(target, key),
                    readOnly = Schema.reason(target, key) ~= nil,
                    reason = Schema.reason(target, key),
                    options = Schema.options(target, key),
                    colorMaximum = Schema.colorMaximum(target, key),
                }
            elseif (key == 'geometry' or key == 'material') and value ~= nil then
                result[#result + 1] = {
                    key = key,
                    kind = 'string',
                    value = key == 'material' and (value.kind or 'Custom material')
                        or 'Geometry resource',
                    readOnly = true,
                    reason = key == 'material'
                            and 'Expand the Material child to edit its uniforms.'
                        or 'Replace geometry through the resource API.',
                }
            elseif key == 'colorStops' and kind == 'table' then
                result[#result + 1] = { key = key, kind = 'gradient', value = value }
            elseif
                kind == 'userdata'
                and target.isA
                and target:isA('SurfaceAppearance3D')
                and key:match('Map$')
            then
                result[#result + 1] = {
                    key = key,
                    kind = 'string',
                    value = '<embedded image>',
                    hint = 'Replace with a project image path; an empty path removes this map.',
                }
            elseif kind == 'userdata' then
                result[#result + 1] = {
                    key = key,
                    kind = 'string',
                    value = tostring(value),
                    readOnly = true,
                    reason = 'Runtime resource handle; use the resource API.',
                }
            elseif kind == 'table' and #value >= 2 and #value <= 4 then
                local numeric = true
                for i = 1, #value do
                    numeric = numeric and type(value[i]) == 'number'
                end
                if numeric then
                    result[#result + 1] = {
                        key = key,
                        kind = 'vector',
                        value = value,
                        hint = Schema.hint(target, key),
                        labels = Schema.descriptor(target, key).labels
                            or (key == 'thickness' or key == 'radius' and target:isA('UICorner')) and {
                                'Scale',
                                'Offset',
                            }
                            or nil,
                        colorMaximum = Schema.colorMaximum(target, key),
                        reason = Schema.reason(target, key),
                        readOnly = Schema.reason(target, key) ~= nil,
                    }
                end
            end
        end
        if target._node and target.getAttributeNames then
            local view = target:attributeView()
            for _, name in ipairs(target:getAttributeNames()) do
                local value = target:getAttribute(name)
                local row = {
                    key = name,
                    attribute = true,
                    container = view,
                    hint = 'Attribute: a named value stored on this node (Node:setAttribute).',
                }
                if target:isAttributeReference(name) then
                    row.kind, row.value = 'node', value
                elseif type(value) == 'boolean' or type(value) == 'number' or type(value) == 'string' then
                    row.kind, row.value = type(value), value
                elseif Array.is(value) and #value >= 2 and #value <= 4 and Properties.numeric(value) then
                    row.kind, row.value = 'vector', value
                else
                    row.kind, row.value = 'string', tostring(value)
                    row.readOnly, row.reason = true, 'Only scripts can change this attribute value.'
                end
                result[#result + 1] = row
            end
            result[#result + 1] = {
                key = 'add attribute',
                kind = 'string',
                value = '',
                attribute = true,
                attributeNew = true,
                container = view,
                hint = 'name = value adds or changes an attribute (true, false, a number, "1, 2, 3" for a '
                    .. 'vector, or text); name: node adds an empty node slot; name = (nothing) removes it.',
            }
        end
        require('source.engine.editor.inspectors.blendShapeRows').append(target, result)
        return result
    end
end

return PropertyRead

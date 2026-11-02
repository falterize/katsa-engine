local Array = require('../../math.array')
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
local walk = require('../traversal').each
local Snapshot = require('../../core.valueSnapshot')
local ChangeTracking = {}

function ChangeTracking.install(UI)
    local tangentKinds = { 'incoming', 'outgoing' }
    local colorFields = {
        'color',
        'backgroundColor',
        'imageColor',
        'textColor',
        'tint',
        'position',
        'size',
        'anchorPoint',
        'thickness',
        'tileSize',
        'tileOffset',
        'atlasGrid',
        'textureSize',
        'textureOffset',
    }
    local observed = {
        'layerGroup',
        'zIndex',
        'radius',
        'clip',
        'text',
        'placeholderText',
        'multiline',
        'x',
        'y',
        'width',
        'height',
        'fontSize',
        'font',
        'relativeTo',
        'sizeRelativeTo',
        'positionRelativeTo',
        'backgroundTransparency',
        'imageTransparency',
        'textTransparency',
        'textScaled',
        'richText',
        'minTextSize',
        'maxTextSize',
        'visible',
        'enabled',
        'interactable',
        'image',
        'material',
        'value',
        'align',
        'verticalAlign',
        'padding',
        'target',
        'rotation',
        'transparency',
        'fitMode',
        'pixelate',
        'imageMode',
        'xml',
        'shaderPath',
        'shaderTransparency',
        'shaderLayer',
        'interpolation',
    }

    local scrollKeys = {
        'scrollY',
        'scrollX',
        'scrollingDirection',
        'scrollingEnabled',
        'automaticCanvasSize',
        'horizontalScrollBarInset',
        'verticalScrollBarInset',
        'topImage',
        'midImage',
        'bottomImage',
        'scrollBarThickness',
        'scrollBarImageTransparency',
        'verticalScrollBarPosition',
        'length',
        'automaticLength',
        'contentPadding',
    }
    local scrollVectors = { 'canvasSize', 'canvasPosition', 'scrollBarImageColor3' }
    local canvasVectors = { 'canvasSize' }
    local emptyKeys = {}
    local fixedObserved = {}
    for _, key in ipairs(observed) do
        if key ~= 'text' then
            fixedObserved[#fixedObserved + 1] = key
        end
    end

    -- Schemas are cached by table identity, so these must be stable (a literal leaks per call).
    local noKeys, sizeVectors = {}, { 'size' }

    local function changed(list, paint)
        local result, animated = false, false
        for _, node in ipairs(list) do
            if node:isA('Node2D') then
                node._spatialSnapshot = node._spatialSnapshot or {}
                result = Snapshot.fields(node._spatialSnapshot, node, noKeys, sizeVectors) or result
                local childChanged, childAnimated = changed(node.children, paint)
                result, animated = childChanged or result, childAnimated or animated
            elseif node:isA('UINode') or node:isA('Ramp') then
                local snapshot = node._snapshot
                if not snapshot then
                    snapshot = {}
                    node._snapshot = snapshot
                    result = true
                end
                if Snapshot.scalar(snapshot, 'atlasFrame', node.atlasFrame) then
                    paint.changed = true
                end
                local fixed = node._fixedTextLayout
                result = Snapshot.fields(
                    snapshot,
                    node,
                    fixed and fixedObserved or observed,
                    colorFields
                ) or result
                if fixed and Snapshot.scalar(snapshot, 'text', rawget(node, 'text')) then
                    -- Only explicitly fixed-layout diagnostics opt out of text-driven layout.
                    paint.changed = true
                end
                -- Scroll properties belong to ScrollFrame, not every text glyph/widget.
                local class = rawget(node, '_class')
                local scrollable = rawget(node, 'scrollable')
                if scrollable == nil and class then
                    scrollable = class.scrollable
                end
                if scrollable then
                    snapshot.scroll = snapshot.scroll or {}
                    result = Snapshot.fields(snapshot.scroll, node, scrollKeys, scrollVectors)
                        or result
                elseif
                    rawget(node, 'canvasSize')
                    or (rawget(node, '_typedValues') or Snapshot.empty).canvasSize
                    or class and class.canvasSize
                then
                    snapshot.canvas = snapshot.canvas or {}
                    result = Snapshot.fields(snapshot.canvas, node, emptyKeys, canvasVectors)
                        or result
                end
                if node:isA('UICorner') then
                    local old = snapshot.corner or {}
                    snapshot.corner = old
                    for i = 1, 2 do
                        if old[i] ~= node.radius[i] then
                            old[i] = node.radius[i]
                            result = true
                        end
                    end
                end
                if node:isA('Ramp') then
                    local old = snapshot.gradient or {}
                    snapshot.gradient = old
                    local index = 0

                    local function sample(value)
                        index = index + 1
                        if old[index] ~= value then
                            old[index] = value
                            result = true
                        end
                    end
                    for i = 1, 4 do
                        sample(node.offset[i])
                    end
                    sample(node.points.interpolation)
                    for _, point in ipairs(node.points) do
                        sample(point.time)
                        if Array.is(point.value) then
                            for _, v in ipairs(point.value) do
                                sample(v)
                            end
                        else
                            sample(point.value)
                        end
                        for _, kind in ipairs(tangentKinds) do
                            if point[kind] then
                                sample(point[kind][1])
                                sample(point[kind][2])
                            end
                        end
                    end
                    for key, goal in pairs(node.goals) do
                        sample(key)
                        if Array.is(goal) then
                            for _, value in ipairs(goal) do
                                sample(value)
                            end
                        else
                            sample(goal)
                        end
                    end
                    for key, points in pairs(node.bindings) do
                        sample(key)
                        sample(points.interpolation)
                        for _, point in ipairs(points) do
                            sample(point.time)
                            if Array.is(point.value) then
                                for _, v in ipairs(point.value) do
                                    sample(v)
                                end
                            else
                                sample(point.value)
                            end
                            for _, kind in ipairs(tangentKinds) do
                                if point[kind] then
                                    sample(point[kind][1])
                                    sample(point[kind][2])
                                end
                            end
                        end
                    end
                    if old.count ~= index then
                        old.count = index
                        result = true
                    end
                end
                -- Hidden subtrees are observed again when their root becomes visible.
                local childChanged, childAnimated = false, false
                if node.visible ~= false then
                    childChanged, childAnimated = changed(node.children, paint)
                end
                if childChanged then
                    result = true
                end
                if
                    node.visible
                    and (
                        (node:isA('Shader2D') and node.enabled ~= false and node.shaderPath ~= '')
                        or (node.material and node.material.animated)
                        or childAnimated
                    )
                then
                    animated = true
                end
            end
        end
        return result, animated
    end

    function UI:changed()
        local paint = self._paintChanges or {}
        self._paintChanges = paint
        paint.changed = false
        local modified, animated = changed(self.children, paint)
        self.animated = animated
        if modified then
            self:invalidate()
        elseif paint.changed then
            self:invalidatePaint()
        end
        return self.revision
    end

    function UI:hasAnimatedMaterial()
        local animated = false
        walk(self.children, function(node)
            if node.visible and node.material and node.material.animated then
                animated = true
            end
        end)
        return animated
    end
end

return ChangeTracking

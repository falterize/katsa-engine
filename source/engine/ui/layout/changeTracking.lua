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

    -- Sparse scan: a node only reads the observed keys it actually has (set on the node, typed, or
    -- seen before). Every other key is the class default, which cannot change, so reading it
    -- every layout was wasted work. A key that appears later arrives through `__newindex`
    -- (it sets `_watchDirty`) or `ValueTypes.assign` (it bumps `_propertyRevision`); both make
    -- the node rebuild its key list on the next scan. Lists are shared by signature, so the
    -- compiled snapshot schemas stay few.
    local schemas = {}

    local function schemaFor(node, snapshot, fixed)
        local revision = rawget(node, '_propertyRevision')
        if
            snapshot._schema
            and snapshot._schemaRevision == revision
            and not rawget(node, '_watchDirty')
        then
            return snapshot._schema
        end
        rawset(node, '_watchDirty', nil)
        local typed = rawget(node, '_typedValues')
        local class = rawget(node, '_class')
        local source = fixed and fixedObserved or observed
        local keys, vectors, names = {}, {}, {}
        for _, key in ipairs(source) do
            if
                rawget(node, key) ~= nil
                or (typed and typed[key] ~= nil)
                or snapshot[key] ~= nil
                or (key == 'enabled' and class and class.getEnabled)
            then
                keys[#keys + 1] = key
                names[#names + 1] = key
            end
        end
        names[#names + 1] = '|'
        for _, key in ipairs(colorFields) do
            if
                rawget(node, key) ~= nil
                or (typed and typed[key] ~= nil)
                or snapshot[key] ~= nil
                or (class and class[key] ~= nil)
            then
                vectors[#vectors + 1] = key
                names[#names + 1] = key
            end
        end
        local signature = table.concat(names, ',')
        local schema = schemas[signature]
        if not schema then
            schema = { keys = keys, vectors = vectors }
            schemas[signature] = schema
        end
        snapshot._schema, snapshot._schemaRevision = schema, revision
        return schema
    end

    local function changed(list, paint)
        local result, animated = false, false
        for _, node in ipairs(list) do
            -- Type tests read the class table directly: node:isA() goes through the property
            -- lookup of every node, and this scan visits every node of the UI every layout.
            local types = rawget(node, '_class')._types
            if types.Node2D then
                node._spatialSnapshot = node._spatialSnapshot or {}
                result = Snapshot.fields(node._spatialSnapshot, node, noKeys, sizeVectors) or result
                local childChanged, childAnimated = changed(node.children, paint)
                result, animated = childChanged or result, childAnimated or animated
            elseif types.UINode or types.Ramp then
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
                local schema = schemaFor(node, snapshot, fixed)
                result = Snapshot.fields(snapshot, node, schema.keys, schema.vectors) or result
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
                if types.UICorner then
                    local old = snapshot.corner or {}
                    snapshot.corner = old
                    for i = 1, 2 do
                        if old[i] ~= node.radius[i] then
                            old[i] = node.radius[i]
                            result = true
                        end
                    end
                end
                if types.Ramp then
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
                    types.UINode
                    and node.visible ~= false
                    and (
                        (types.Shader2D and node.enabled ~= false and node.shaderPath ~= '')
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
            if node:isA('UINode') and node.visible ~= false and node.material and node.material.animated then
                animated = true
            end
        end)
        return animated
    end
end

return ChangeTracking

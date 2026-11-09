local ipairs = require('../math.array').ipairs
-- Shared sampler/mode policy; variants never mutate an image owned by another node.
local Image = {}

function Image.initialize(node)
    node.imageMode = node.imageMode or 'Decal'
    node.xml = node.xml or ''
    node.fitMode = node.fitMode or 'Stretch'
    if node.fitMode == 'Tile' and node.mode == nil then
        node.imageMode = 'Tiles'
        node.fitMode = 'Stretch'
    end
    if node.pixel ~= nil and node.pixelate == nil then
        node.pixelate = node.pixel
    end
    node.pixelate = node.pixelate == true
    node.pixel = nil
    node.tileSize = node.tileSize or { 0, 32, 0, 32 }
    node.tileOffset = node.tileOffset or { 0, 0 }
    node.textureSize = node.textureSize or { 32, 32 }
    node.textureOffset = node.textureOffset or { 0, 0 }
    node.atlasGrid = node.atlasGrid or { 1, 1 }
    node.atlasFrame = node.atlasFrame or 0
end

function Image.pixelate(node)
    return node.pixelate == true
end

function Image.resolve(resources, node, source, environment)
    source = source or node.image
    if node.imageMode == 'XML' then
        local attempt = node._xmlAttempt
        if
            not attempt
            or attempt.path ~= node.xml
            or attempt.source ~= source
            or attempt.resources ~= resources
        then
            local ok, definition = pcall(
                require('source.engine.animation.formats.flipbookXml').bind,
                resources,
                node,
                source
            )
            local resolved = ok and node._xmlBinding.image or 'assets/textures/internal/missing.png'
            if not ok and resources.store.journal then
                resources.store.journal:record(
                    'Resources',
                    tostring(definition),
                    node,
                    tostring(node.xml)
                )
            end
            attempt = {
                path = node.xml,
                source = ok and node._xmlBinding.source or source,
                resources = resources,
                image = resolved,
            }
            node._xmlAttempt = attempt
        end
        source = attempt.image
    elseif source == nil or source == '' then
        -- Preserve the last resolved sprite when leaving XML mode, even if no
        -- explicit image override was authored. Do not write over that property.
        if not node._xmlBinding and node.xml and node.xml ~= '' then
            pcall(require('source.engine.animation.formats.flipbookXml').bind, resources, node)
        end
        source = node._xmlBinding and node._xmlBinding.image or source
    end
    local pixel = Image.pixelate(node, environment)
    if node._samplerSource == source and node._samplerPixel == pixel then
        return node._samplerImage
    end
    if source == nil or type(source) == 'string' then
        local image = resources:imageVariant(source, pixel)
        node._imageMissing = resources:isMissingImage(source)
        node._samplerSource, node._samplerPixel, node._samplerImage = source, pixel, image
        return image
    end
    node._imageMissing = false
    local filter = pixel and 'nearest' or 'linear'
    local min, mag = source:getFilter()
    if min == filter and mag == filter then
        return source
    end
    resources.samplerVariants = resources.samplerVariants or {}
    local variants = resources.samplerVariants[source] or {}
    resources.samplerVariants[source] = variants
    local variant = variants[filter]
    if not variant then
        local g = katsa.graphics
        local w, h = source:getDimensions()
        variant = resources:own(g.newCanvas(w, h))
        g.push('all')
        g.setCanvas(variant)
        g.origin()
        g.setScissor()
        g.setStencilTest()
        g.setDepthMode()
        g.setShader()
        g.clear(0, 0, 0, 0)
        g.setColor(1, 1, 1, 1)
        g.setBlendMode('alpha', 'premultiplied')
        g.draw(source)
        g.pop()
        require('source.engine.graphics.state').reapplyScissor()
        variant:setFilter(filter, filter)
        variant:setWrap('repeat', 'repeat')
        variants[filter] = variant
    end
    return variant
end

function Image.region(node, iw, ih, frameOverride)
    if node._imageMissing then
        return 0, 0, iw, ih
    end
    if node.imageMode ~= 'Atlas' and node.imageMode ~= 'XML' and frameOverride == nil then
        return 0, 0, iw, ih
    end
    local cols, rows = node.atlasGrid[1], node.atlasGrid[2]
    assert(
        cols >= 1 and rows >= 1 and cols == math.floor(cols) and rows == math.floor(rows),
        'Atlas grid requires positive integer dimensions'
    )
    local frame = math.floor(frameOverride or node.atlasFrame or 0) % (cols * rows)
    return frame % cols * iw / cols, math.floor(frame / cols) * ih / rows, iw / cols, ih / rows
end

-- Shared UV origin/extent in normalized texture coordinates. Destination size
-- is supplied in the caller's units (UI pixels or spatial particle/decal units).
function Image.uv(node, iw, ih, width, height, frame, selectedMode)
    if node._imageMissing then
        return 0, 0, 1, 1
    end
    local mode = selectedMode or node.imageMode or node.mode or 'Decal'
    if mode == 'Atlas' or mode == 'XML' then
        local x, y, w, h = Image.region(node, iw, ih, frame)
        return x / iw, y / ih, w / iw, h / ih
    elseif mode == 'Texture' then
        local size, offset = node.textureSize, node.textureOffset
        assert(size[1] > 0 and size[2] > 0, 'TextureSize must be positive')
        return -offset[1] / size[1], -offset[2] / size[2], width / size[1], height / size[2]
    elseif mode == 'Tiles' then
        if node._legacyTileFit then
            local x, y, w, h =
                require('source.engine.ui.drawing.image').rect(node.fitMode, width, height, iw, ih)
            return -x / w, -y / h, width / w, height / h
        end
        local tw, th =
            require('source.engine.ui.layout.metrics').resolve(node.tileSize, width, height)
        assert(tw > 0 and th > 0, 'TileSize must be positive')
        return -node.tileOffset[1] / tw, -node.tileOffset[2] / th, width / tw, height / th
    end
    return 0, 0, 1, 1
end

function Image.describe(class)
    -- rawget: the class inherits through its base, so a plain read would mutate the parent's schema.
    local schema = rawget(class, 'propertySchema') or {}
    class.propertySchema = schema
    schema.fitMode = {
        options = { 'Fit', 'Crop', 'Stretch' },
        visibleWhen = { key = 'imageMode', oneOf = { 'Decal', 'Atlas', 'XML' } },
    }
    schema.imageMode = { options = { 'Decal', 'Texture', 'Tiles', 'Atlas', 'XML' } }
    schema.xml = { visibleWhen = { key = 'imageMode', equals = 'XML' } }
    if class.name == 'ImageRect' or class.name == 'Button' then
        schema.image = {
            get = function(node)
                return node.image or ''
            end,
            hint = 'Optional image override. An empty path uses the XML manifest image in XML '
                .. 'mode.',
        }
    end
    schema.pixelate = {
        get = function(node)
            return Image.pixelate(node)
        end,
    }
    for _, key in ipairs({ 'tileSize', 'tileOffset' }) do
        schema[key] = { visibleWhen = { key = 'imageMode', equals = 'Tiles' } }
    end
    for _, key in ipairs({ 'textureSize', 'textureOffset' }) do
        schema[key] = { visibleWhen = { key = 'imageMode', equals = 'Texture' } }
    end
    for _, key in ipairs({ 'atlasGrid', 'atlasFrame' }) do
        schema[key] = { visibleWhen = { key = 'imageMode', equals = 'Atlas' } }
    end
    schema.atlasFrame = { visibleWhen = { key = 'imageMode', oneOf = { 'Atlas', 'XML' } } }
end

function Image.bindUV(shader, node, image)
    if not shader:hasUniform('imageUVScale') then
        return
    end
    if node and node.isA and node:isA('Decal3D') then
        shader:send('imageUVScale', { 1, 1 })
        shader:send('imageUVOffset', { 0, 0 })
        return
    end
    local sx, sy, ox, oy = 1, 1, 0, 0
    local mode = node and node.imageMode or 'Decal'
    local size = node and (node.size or node.parent and node.parent.size) or { 1, 1, 1 }
    local iw, ih = image:getDimensions()
    local width, height = math.abs(size[1]), math.abs(size[2])
    if mode == 'Tiles' then
        width, height = width * 16, height * 16
    end
    ox, oy, sx, sy = Image.uv(node, iw, ih, width, height)
    shader:send('imageUVScale', { sx, sy })
    shader:send('imageUVOffset', { ox, oy })
end

return Image

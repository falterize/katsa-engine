local readValue = require('../math.managedValue').read
local ipairs = require('../math.array').ipairs
local Image = require('../components.image')
local Bounds = require('../graphics.geometry.objectBounds')

local Surface = {}
local scalarKeys = {
    'transparency',
    'colorMap',
    'normalMap',
    'roughnessMap',
    'metalnessMap',
    'occlusionMap',
    'emissionMap',
    'roughness',
    'metalness',
    'normalScale',
    'occlusionStrength',
    'emissionStrength',
    'pixelate',
    'alphaMode',
    'alphaCutoff',
    'imageMode',
    'xml',
    'fitMode',
    'atlasFrame',
}
local vectorKeys = {
    'color',
    'emissionColor',
    'atlasGrid',
    'textureSize',
    'textureOffset',
    'tileSize',
    'tileOffset',
}
local maps = { 'normalMap', 'roughnessMap', 'metalnessMap', 'occlusionMap', 'emissionMap' }

function Surface.compatible(a, b)
    if a == b then
        return true
    end
    if not a or not b then
        return false
    end
    for _, key in ipairs(scalarKeys) do
        if a[key] ~= b[key] then
            return false
        end
    end
    for _, key in ipairs(vectorKeys) do
        local av, bv = readValue(a[key]), readValue(b[key])
        if av ~= bv then
            if not av or not bv or #av ~= #bv then
                return false
            end
            for i = 1, #av do
                if av[i] ~= bv[i] then
                    return false
                end
            end
        end
    end
    return true
end

function Surface.resolve(world, object, visible, opacity)
    local active = object._activeSurfaces or {}
    object._activeSurfaces = active
    for i = #active, 1, -1 do
        active[i] = nil
    end
    if visible == nil then
        visible, opacity = object:getVisibilityState()
    end
    if not visible or opacity <= 0 then
        require('source.engine.materials.blend').releaseBuffers(object)
        object._surfaceAppearance = nil
        return nil
    end
    for _, node in ipairs((object._skinOwner or object).children) do
        if
            node:isA('SurfaceAppearance3D')
            and node.enabled ~= false
            and require('source.engine.world.visibilityLayers').visible(
                world,
                node,
                world._materialCamera or world.activeCamera
            )
        then
            assert(
                node.transparency >= 0 and node.transparency <= 1,
                'SurfaceAppearance3D.Transparency must be within 0..1'
            )
            assert(
                node.roughness >= 0
                    and node.roughness <= 1
                    and node.metalness >= 0
                    and node.metalness <= 1,
                'Surface material factors must be within 0..1'
            )
            assert(
                node.normalScale >= 0 and node.emissionStrength >= 0,
                'Surface intensity must be nonnegative'
            )
            if node.transparency < 1 then
                active[#active + 1] = node
            end
        end
    end
    assert(
        #active <= 4,
        'At most four contributing SurfaceAppearance3D nodes per mesh are supported'
    )
    local selected = active[1]
    if #active > 1 or selected and selected.transparency > 0 then
        selected = require('source.engine.materials.blend').resolve(world, object, active)
    else
        require('source.engine.materials.blend').releaseBuffers(object)
    end
    object._surfaceAppearance = selected
    return selected
end

function Surface.image(resources, node, key, environment)
    if node.imageMode == 'XML' then
        if key == 'colorMap' then
            return Image.resolve(resources, node, node.colorMap, environment)
        end
        require('source.engine.animation.formats.flipbookXml').bind(resources, node, node.colorMap)
    end
    local source = node[key]
    if source == '' or source == nil then
        if key == 'colorMap' then
            if node._xmlBinding then
                return Image.resolve(resources, node, source, environment)
            end
            node._imageMissing = false
        end
        return
    end
    node._mapSamplers = node._mapSamplers or {}
    local sampler = node._mapSamplers[key] or {}
    node._mapSamplers[key] = sampler
    sampler.pixelate = node.pixelate
    local image = Image.resolve(resources, sampler, source, environment)
    if key == 'colorMap' then
        node._imageMissing = sampler._imageMissing
    end
    return image
end

function Surface.bind(shader, world, object)
    if not shader:hasUniform('surfaceEnabled') and not shader:hasUniform('surfaceColor') then
        return
    end
    local node = object and object._surfaceAppearance
    if shader:hasUniform('surfaceEnabled') then
        shader:send('surfaceEnabled', node ~= nil)
    end
    shader:send('surfaceMissing', false)
    if not node then
        return
    end
    local fallback = world.resources:image('white')
    local missing = node._missing
        or node._imageMissing
        or type(node.colorMap) == 'string'
            and node.colorMap ~= ''
            and world.resources:isMissingImage(node.colorMap)
    for _, key in ipairs(maps) do
        local image = Surface.image(world.resources, node, key, world.environment)
        if
            type(node[key]) == 'string'
            and node[key] ~= ''
            and world.resources:isMissingImage(node[key])
        then
            missing = true
        end
        local suffix = key:sub(1, 1):upper() .. key:sub(2)
        if shader:hasUniform('surface' .. suffix) then
            shader:send('surface' .. suffix, image or fallback)
        end
        if shader:hasUniform('has' .. suffix) then
            shader:send('has' .. suffix, image ~= nil)
        end
    end
    assert(
        node.roughness >= 0 and node.roughness <= 1 and node.metalness >= 0 and node.metalness <= 1,
        'Surface material factors must be within 0..1'
    )
    assert(
        node.normalScale >= 0 and node.emissionStrength >= 0,
        'Surface intensity must be nonnegative'
    )
    shader:send('surfaceMissing', missing == true)
    if missing and shader:hasUniform('surfaceDiagnosticBounds') then
        local bounds = Bounds.localBounds(object.geometry)
        local extent = math.max(bounds[4] - bounds[1], bounds[5] - bounds[2], bounds[6] - bounds[3])
        local diagnostic = object._diagnosticBounds or {}
        object._diagnosticBounds = diagnostic
        -- Twelve cells across the rest mesh keep the pattern stable through skinning,
        -- object movement and scaling, without depending on authored UVs.
        diagnostic[1], diagnostic[2], diagnostic[3] = bounds[1], bounds[2], bounds[3]
        diagnostic[4] = 12 / math.max(extent, 0.000001)
        shader:send('surfaceDiagnosticBounds', diagnostic)
    end
    local color = node._uniformColor or {}
    node._uniformColor = color
    for i = 1, #node.color do
        color[i] = node.color[i]
    end
    for i = #color, #node.color + 1, -1 do
        color[i] = nil
    end
    shader:send('surfaceColor', color)
    local factors = node._uniformFactors or {}
    local emission = node._uniformEmission or {}
    node._uniformFactors, node._uniformEmission = factors, emission
    factors[1], factors[2], factors[3], factors[4] =
        node.roughness, node.metalness, node.normalScale, node.occlusionStrength
    emission[1], emission[2], emission[3], emission[4] =
        node.emissionColor[1], node.emissionColor[2], node.emissionColor[3], node.emissionStrength
    shader:send('surfaceFactors', factors)
    shader:send('surfaceEmission', emission)
    if shader:hasUniform('surfacePackedMR') then
        shader:send('surfacePackedMR', node._packedMR == true)
    end
    shader:send('surfaceOpaque', node.alphaMode == 'Opaque')
end

return Surface

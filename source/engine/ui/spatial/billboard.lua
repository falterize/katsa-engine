local ipairs = require('source.engine.math.array').ipairs
local M = require('source.engine.math.math3d')
local UI = require('source.engine.ui')
local Node = require('source.engine.nodes')
local Validate = require('source.engine.core.validate')

local BillboardUI = Node.getClass('BillboardUI')
BillboardUI.__index = BillboardUI

function BillboardUI.new(world, settings)
    assert(settings.name, 'BillboardUI needs a name')
    local class = settings._registeredClass
    local surface = settings.className == 'SurfaceUI'
    while class do
        if class.name == 'SurfaceUI' then
            surface = true
        end
        class = class.base
    end
    if surface then
        settings.spatialPosition = settings.spatialPosition or { 0, 0, 0 }
        settings.position = settings.position or { 0.5, 0, 0.5, 0 }
    else
        -- Explicit v49 loader compatibility: screen layout and spatial pose are separate.
        if settings.position and #settings.position == 4 then
            settings.screenPosition = settings.position
            settings.position = nil
        end
        settings.position = settings.position or settings.spatialPosition or { 0, 0, 0 }
        settings.spatialPosition = nil
        settings.screenPosition = settings.screenPosition or settings.screenOffset or { 0, 0, 0, 0 }
        settings.offset = settings.offset or { 0, 0, 0 }
        settings.offsetWorldSpace = settings.offsetWorldSpace or { 0, 0, 0 }
        settings.extentsOffset = settings.extentsOffset or { 0, 0, 0 }
        settings.extentsOffsetWorldSpace = settings.extentsOffsetWorldSpace or { 0, 0, 0 }
        for _, key in ipairs({
            'position',
            'offset',
            'offsetWorldSpace',
            'extentsOffset',
            'extentsOffsetWorldSpace',
        }) do
            Validate.vector(settings[key], 'BillboardUI.' .. key, 3)
        end
    end
    settings.screenOffset = nil
    settings.brightness = settings.brightness or 1
    settings.supportSize = settings.supportSize or { 1, 1, 1 }
    Validate.vector(settings.supportSize, 'Adornment.supportSize', 3)
    for i = 1, 3 do
        assert(settings.supportSize[i] > 0, 'Adornment.supportSize must be positive')
    end
    assert(
        type(settings.brightness) == 'number'
            and settings.brightness >= 0
            and settings.brightness < math.huge,
        'Adornment.brightness must be finite and nonnegative'
    )
    local adornee = settings.adornee
    if type(adornee) == 'string' then
        adornee = assert(world.byName[adornee], 'Unknown legacy Adornee name: ' .. adornee)
    end
    if adornee then
        local ok, reason =
            require('source.engine.surfaces.support').valid({ _world = world }, adornee)
        assert(ok, reason)
    end
    rawset(settings, 'adornee', nil)
    if settings.scale then
        assert(
            settings.scale[1] == 1 and settings.scale[2] == 1 and settings.scale[3] == 1,
            'World3D UI uses Size; independent scale is unsupported'
        )
    end
    settings.size = settings.size or { 0, 240, 0, 120 }
    if #settings.size == 2 then
        settings.size = { 0, settings.size[1], 0, settings.size[2] }
    end
    settings.anchorPoint = settings.anchorPoint or { 0.5, 0.5 }
    settings.relativeTo = settings.relativeTo or 'XY'
    settings.sizeMode = settings.sizeMode or 'Screen'
    settings.canvasSize = settings.canvasSize or { 0, 240, 0, 120 }
    if #settings.canvasSize == 2 then
        settings.canvasSize = { 0, settings.canvasSize[1], 0, settings.canvasSize[2] }
    end
    settings.canvasPixelsPerUnit = settings.canvasPixelsPerUnit or 16
    settings.resolvedCanvasSize =
        { math.max(1, settings.canvasSize[2]), math.max(1, settings.canvasSize[4]) }
    assert(
        #settings.position == (surface and 4 or 3) and #settings.size == 4,
        'Invalid BillboardUI Position/Size dimensions'
    )
    Validate.vector(settings.canvasSize, 'BillboardUI.canvasSize', 4)
    assert(
        settings.resolvedCanvasSize[1] > 0 and settings.resolvedCanvasSize[2] > 0,
        'BillboardUI canvasSize must be positive'
    )
    settings.onTop = settings.onTop ~= false
    settings.visible = settings.visible ~= false
    settings.zIndex = settings.zIndex or 0
    settings.enabled = settings.enabled ~= false
    settings.debugEnabled = settings.debugEnabled == true
    settings.transparency = settings.transparency or 0
    settings.maxDistance = settings.maxDistance or 500
    settings.interactable = settings.interactable ~= false and settings.interactive ~= false
    settings.interactive = nil
    settings.worldPosition = {}
    settings.matrix = M.identity()
    settings.normal = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
    settings.ui =
        UI.new(settings.resolvedCanvasSize[1], settings.resolvedCanvasSize[2], world.resources)
    settings.textureLimit = love.graphics.getSystemLimits().texturesize
    local initialLimit = math.min(settings.maxTextureSize or 2048, settings.textureLimit)
    local initialRatio = math.min(
        1,
        initialLimit / settings.resolvedCanvasSize[1],
        initialLimit / settings.resolvedCanvasSize[2]
    )
    settings.resolvedCanvasSize[1] =
        math.max(1, math.floor(settings.resolvedCanvasSize[1] * initialRatio))
    settings.resolvedCanvasSize[2] =
        math.max(1, math.floor(settings.resolvedCanvasSize[2] * initialRatio))
    settings.ui.width, settings.ui.height =
        settings.resolvedCanvasSize[1], settings.resolvedCanvasSize[2]
    settings.canvasDensity = math.min(
        2,
        math.min(settings.maxTextureSize or 2048, settings.textureLimit)
            / math.max(settings.resolvedCanvasSize[1], settings.resolvedCanvasSize[2])
    )
    settings.ui:setDensity(settings.canvasDensity)
    settings.canvasAllocationWidth, settings.canvasAllocationHeight =
        settings.resolvedCanvasSize[1], settings.resolvedCanvasSize[2]
    settings.canvas = world.resources:own(
        love.graphics.newCanvas(
            settings.resolvedCanvasSize[1],
            settings.resolvedCanvasSize[2],
            { dpiscale = settings.canvasDensity }
        )
    )
    settings.canvas:setFilter('linear', 'linear')
    settings.resources = world.resources
    settings.bounds = { 0, 0, settings.resolvedCanvasSize[1], settings.resolvedCanvasSize[2] }
    settings.dirty = true
    local owner = settings.parent or rawget(settings, 'attachment') or world.folders.Billboards
    rawset(settings, 'parent', nil)
    local node =
        Node.adopt(setmetatable(settings, BillboardUI), settings.className or 'BillboardUI')
    if not surface then
        local vectors = {}
        for _, key in ipairs({
            'position',
            'offset',
            'offsetWorldSpace',
            'extentsOffset',
            'extentsOffsetWorldSpace',
        }) do
            vectors[key] = require('source.engine.math.managedValue').bind(
                require('source.engine.math.vector3').fromArray(rawget(node, key)),
                node
            )
            rawset(node, key, nil)
        end
        node._billboardVectors = vectors
    end
    node._world = world
    node:onDestroy(function()
        node.ui:release()
        world:removeBillboard(node)
    end)

    node.inheritScale = settings.inheritScale == true
    require('source.engine.surfaces.support').initialize(node, adornee)
    node.parent = owner
    node.layers = node.layers or 1
    node.ui:bindBillboard(node)
    world.billboards[#world.billboards + 1] = node
    return node
end
require('source.engine.ui.spatial.billboardCanvas').install(BillboardUI)
require('source.engine.ui.spatial.billboardProjection').install(BillboardUI)
require('source.engine.ui.spatial.billboardPicking').install(BillboardUI)
return BillboardUI

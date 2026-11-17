local band, bor = require('bit').band, require('bit').bor
local Renderer = require('./renderer')
local SceneTextures = require('./sceneTextures')

-- A second render of the 3D scene that draws only some layer groups, for a Shader2D that names
-- them in `viewLayers` (`hint_layer_texture`: colour, alpha 1 where a layer object was drawn;
-- `hint_layer_depth_texture`: its opaque depth). It is the Godot recipe of a camera with a
-- `cull_mask` in a SubViewport: the camera is the main one with a narrower `layers` mask, and
-- the target is a separate renderer at half the main density. It shares the main shadow atlas,
-- draws no sky, gizmos, post effects, interface or transparent objects (those stay in the
-- main pass). Passes are keyed by the mask, so
-- two shaders with the same groups share one pass, and a pass is made at most once per frame.
local LayerPass = {}

-- The bit mask of `names` (a comma separated string or a table), or nil for none.
function LayerPass.mask(world, names)
    if type(names) == 'string' then
        local list = {}
        for name in names:gmatch('[^,%s]+') do
            list[#list + 1] = name
        end
        names = list
    end
    if not names or #names == 0 then
        return nil
    end
    local registry = world.layerGroups
    local mask = 0
    for _, name in ipairs(names) do
        local group = registry:canonical(name)
        assert(registry.bits[group], 'Unknown layer group in viewLayers: ' .. tostring(name))
        mask = bor(mask, registry.bits[group])
    end
    return mask
end

local function passes(ui)
    local list = ui._layerPasses
    if not list then
        list = {}
        ui._layerPasses = list
    end
    return list
end

-- The colour canvas and the readable depth of the pass for `mask`, drawn from `main` (the
-- renderer that produced this frame's 3D background).
function LayerPass.get(ui, main, mask)
    local pass = passes(ui)[mask]
    if not pass then
        local renderer = Renderer.new(ui.resources)
        renderer.layerPass = true
        renderer.shadows = main.shadows
        renderer.depthPrepass = false
        -- `update` does nothing: the proxy shares the main camera's matrices exactly as the main pass
        -- used them. Recomputing them here moved a camera that follows its target between the
        -- two passes, and the layer drifted away from the object by the camera's step.
        local proxy = setmetatable({ layers = mask, update = function() end }, {})
        pass = { renderer = renderer, proxy = proxy }
        passes(ui)[mask] = pass
    end
    local renderer = pass.renderer
    if pass.source ~= main.camera then
        pass.source = main.camera
        getmetatable(pass.proxy).__index = main.camera
    end
    renderer.layerDensity = math.max(0.5, main.density * 0.5)
    renderer.renderDensity, renderer.msaa = renderer.layerDensity, 0
    renderer:resize(main.width, main.height)
    if pass.frame ~= main.frame then
        pass.frame = main.frame
        local world = main.world
        -- Drawing marks the world as drawn by this renderer and camera; the main renderer's frame
        -- cache and the interface still belong to the main pass.
        local owner, revision, shadows = world._renderDependencyOwner, world._renderDependencyRevision, world._shadowDependencyRevision
        local camera, active = world._materialCamera, world._activeRenderer
        pass.color = renderer:draw(world, pass.proxy, main.time, true)
        world._renderDependencyOwner, world._renderDependencyRevision = owner, revision
        world._shadowDependencyRevision = shadows
        world._materialCamera, world._activeRenderer = camera, active
    end
    return pass.color, SceneTextures.depth(renderer)
end

-- One transparent pixel: what a shader sees when no layer is named (or there is no 3D scene).
function LayerPass.empty(ui)
    if not ui._emptyLayer then
        local data = katsa.image.newImageData(1, 1, 'rgba8')
        data:setPixel(0, 0, 0, 0, 0, 0)
        ui._emptyLayer = ui.resources:own(katsa.graphics.newImage(data))
    end
    return ui._emptyLayer
end

function LayerPass.release(ui)
    for _, pass in pairs(ui._layerPasses or {}) do
        pass.renderer:release()
    end
    ui._layerPasses = nil
end

return LayerPass

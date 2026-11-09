-- Post-processing chain between the scene canvas and the screen (or an offscreen result):
--
--   scene -> SSAO -> depth of field -> glow / adjustments / vignette -> FXAA -> output
--
-- Only the enabled passes run; each reads the previous image and writes a pooled canvas, the
-- last one writes the destination. Everything follows the Environment sections described in
-- post/settings.lua. Passes live in post/passes, one effect per file.
local Settings = require('./settings')
local Targets = require('./targets')
local SceneDepth = require('./sceneDepth')

local Post = {}
Post.__index = Post

local SSAO = require('./passes.ssao')
local DOF = require('./passes.dof')
local Finish = require('./passes.finish')
local FXAA = require('./passes.fxaa')

function Post.new()
    return setmetatable({ targets = Targets.new(), shaders = {} }, Post)
end

-- Ordered list of {name, pass} the current settings enable.
local function plan(environment)
    local list = {}
    if environment.ssao.enabled then
        list[#list + 1] = SSAO
    end
    if environment.depthOfField.enabled then
        list[#list + 1] = DOF
    end
    if Finish.needed(environment) then
        list[#list + 1] = Finish
    end
    if environment.render.screenSpaceAA == 'FXAA' then
        list[#list + 1] = FXAA
    end
    return list
end

function Post.enabled(environment)
    return environment ~= nil and environment.ssao ~= nil and Settings.active(environment)
end

-- A cheap value that changes whenever a setting changes; the frame cache compares it to know
-- when a reused frame must be rebuilt.
function Post.signature(environment, out)
    local count = 0
    for _, section in ipairs(Settings.sections) do
        local values = environment[section.field]
        for _, key in ipairs(section.keys) do
            count = count + 1
            out[count] = values[key]
        end
    end
    count = count + 1
    out[count] = environment.render.screenSpaceAA
    for i = count + 1, #out do
        out[i] = nil
    end
    return out
end

local context = {}
context.__index = context

function context:depth()
    self.sceneDepth = self.sceneDepth or SceneDepth.get(self.renderer)
    return self.sceneDepth
end

-- Camera terms the depth-reading shaders need to rebuild view-space positions.
function context:sendCamera(shader)
    local camera = self.camera
    local send = require('source.engine.graphics.post.fullscreen').send
    send(shader, 'depthRange', { camera.projection[11], camera.projection[12] })
    send(shader, 'orthographic', camera.orthographic == true)
    send(shader, 'viewSize', { camera.width, camera.height })
    send(shader, 'focal', camera.focal or 1)
    send(shader, 'pixelsPerUnit', camera.pixelsPerUnit or 1)
end

-- Runs the chain. Returns the finished canvas when `offscreen`, nil after drawing to the screen.
function Post:apply(renderer, offscreen)
    local environment = renderer.world.environment
    local passes = plan(environment)
    local ctx = setmetatable({
        post = self,
        renderer = renderer,
        camera = renderer.camera,
        environment = environment,
    }, context)
    local image = renderer.canvas
    local ping, pong = nil, nil
    for index, pass in ipairs(passes) do
        local destination
        if index == #passes then
            destination = offscreen and Targets.get(self.targets, renderer, 'output', 1) or nil
        else
            ping = ping or Targets.get(self.targets, renderer, 'ping', 1)
            pong = pong or Targets.get(self.targets, renderer, 'pong', 1)
            destination = image == ping and pong or ping
        end
        pass.run(ctx, image, destination)
        image = destination
    end
    self.result = image
    return image
end

function Post:release()
    Targets.release(self.targets)
    self.shaders, self.lut, self.lutPath, self.result = {}, nil, nil, nil
end

return Post

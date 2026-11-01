-- Shared renderer state. Category modules attach their functions to the same `G` table and read
-- their mutable state from here; `onSetup` hooks receive the GL bindings once the context exists.
local ffi = require('ffi')
local Texture = require('source.katsa.graphics.texture')

ffi.cdef([[
typedef struct { float x, y, u, v; uint8_t r, g, b, a; } KatsaVertex;
]])

local State = {
    G = {},
    VERTEX_CAPACITY = 12288,
    ready = false,
    screenshots = {},
    setupHooks = {},
}

State.S = {
    color = { 1, 1, 1, 1 },
    background = { 0, 0, 0, 1 },
    blend = 'alpha',
    alphaMode = 'alphamultiply',
    colorMask = { true, true, true, true },
    scissor = nil,
    stencilTest = nil,
    depthCompare = 'always',
    depthWrite = false,
    cull = 'none',
    winding = 'ccw',
    wireframe = false,
    lineWidth = 1,
    lineJoin = 'miter',
    lineStyle = 'smooth',
    shader = nil,
    font = nil,
    canvases = nil, -- list of canvases, nil = backbuffer
    canvasOptions = nil,
    transform = { 1, 0, 0, 1, 0, 0 },
    stack = {},
    pointSize = 1,
}
State.G._state = State.S

State.batch = { count = 0, texture = nil, vertices = nil }
State.stats = { drawcalls = 0, drawcallsbatched = 0, canvasswitches = 0, shaderswitches = 0 }
State.counters = { images = 0, canvases = 0, fonts = 0, texturememory = 0 }
State.target = { w = 1, h = 1, dpi = 1, isCanvas = false }
Texture.counters = State.counters

function State.onSetup(hook)
    State.setupHooks[#State.setupHooks + 1] = hook
end

function State.runSetup(core)
    for _, hook in ipairs(State.setupHooks) do
        hook(core)
    end
end

function State.flush()
    if State.batch.count > 0 then
        State.G._flushBatch()
    end
end

function State.requireReady()
    if not State.ready then
        error('Graphics is not initialised: create a window first (katsa.window.setMode)', 3)
    end
end

return State

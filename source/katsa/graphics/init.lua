-- katsa.graphics: LÖVE-compatible 2D renderer on OpenGL 3.3 core / GLES 3.0.
--
-- Coordinates are in logical units (pixels / dpi scale), y points down. Rendering into a canvas flips
-- the projection so canvas rows run top to bottom; raw clip-space output from custom vertex shaders is
-- left untouched, so canvas contents of 3D passes keep their GL orientation.
--
-- Each category module attaches its functions to the shared table from state.lua. Modules are
-- listed in dependency order; the window hook is attached last because it can create the GL state.
local State = require('source.katsa.graphics.state')

local modules = {
    'transform',
    'color',
    'renderState',
    'shaderApi',
    'canvas',
    'clear',
    'batch',
    'quad',
    'draw',
    'primitives',
    'spriteBatch',
    'text',
}

for _, name in ipairs(modules) do
    require('source.katsa.graphics.' .. name)
end

require('source.katsa.graphics.frame').attach()

return State.G

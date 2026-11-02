-- The front-face winding must reach the driver even when culling is off: gl_FrontFacing still
-- depends on it (double-sided meshes flip their normals with it).
local ffi = require('ffi')

local Module = {}

local function driverFrontFace(core)
    local value = ffi.new('GLint[1]')
    core.gl.glGetIntegerv(0x0B46, value)
    return value[0]
end

function Module.run(self)
    local g = katsa.graphics
    local core = require('source.katsa.graphics.core')
    g.push('all')
    g.setMeshCullMode('none')
    g.setFrontFaceWinding('ccw')
    local first = driverFrontFace(core)
    g.setFrontFaceWinding('cw')
    local second = driverFrontFace(core)
    g.pop()
    self:check(first ~= second, 'winding changes reach the driver while culling is off')
end

return Module

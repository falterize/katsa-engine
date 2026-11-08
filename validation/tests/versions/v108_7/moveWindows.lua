-- Several windows can be moved in one call; their own moves are not taken for a drag.
local Module = {}

function Module.run(self)
    local a = katsa.window.create(120, 90, { title = 'A', x = 10, y = 10 })
    local b = katsa.window.create(120, 90, { title = 'B', x = 20, y = 20 })
    katsa.window.moveWindows({ { a, 200, 150 }, { b, 320, 210 } })
    local ax, ay = a:getPosition()
    local bx, by = b:getPosition()
    self:check(ax == 200 and ay == 150 and bx == 320 and by == 210, 'moveWindows places every window')
    local platform = katsa.platform
    local requested = platform.requested[platform.sdl.SDL_GetWindowID(a._record.raw)]
    self:check(requested and requested[1] == 200 and requested.kind == 'move', 'A requested move is remembered for the live-resize watch')
    a:close()
    b:close()
end

return Module

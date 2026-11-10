-- A scene's server/ and shared code must not reach client code (views, UI, input, cameras, walker
-- visuals) or draw: a dedicated server has no window, and a client-only require would break it.
local FORBIDDEN = {
    'scripts%.view', 'scripts%.ui', 'scripts%.cameras', 'scripts%.controller', 'scripts%.walker',
    'scripts%.content', 'scripts%.game%.gameClient', 'scripts%.game%.voice', 'katsa%.graphics',
    'katsa%.window', 'katsa%.keyboard', 'katsa%.mouse',
}

local function scan(path, found)
    for _, name in ipairs(katsa.filesystem.getDirectoryItems(path)) do
        local full = path .. '/' .. name
        if katsa.filesystem.getInfo(full, 'directory') then
            scan(full, found)
        elseif name:match('%.lua$') then
            local text = katsa.filesystem.read(full)
            for _, pattern in ipairs(FORBIDDEN) do
                if text:find(pattern) then
                    found[#found + 1] = full .. ' uses ' .. pattern:gsub('%%', '')
                end
            end
            for module in text:gmatch("require%('([^']+)'%)") do
                if module:find('view', 1, true) and module:find('%.%./') then
                    found[#found + 1] = full .. ' requires ' .. module
                end
            end
        end
    end
end

local M = {}

function M.run(self)
    local root = 'source/game/scenes/multiplayerCars'
    local found = {}
    for _, folder in ipairs({ '/server', '/scripts/shared', '/nodes/vehicle' }) do
        scan(root .. folder, found)
    end
    self:check(#found == 0, 'server and shared code stay free of client code' .. table.concat(found, '; '))
end

return M

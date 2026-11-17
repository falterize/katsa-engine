-- Scene modules: the debug and editor UI is an optional module under game/, not part of the
-- runtime. A scene built without modules still loads, runs and handles input.
local Application = require('game.runtime.application')

local Module = {}

local function sources(root, out)
    for _, name in ipairs(katsa.filesystem.getDirectoryItems(root)) do
        local path = root .. '/' .. name
        local info = katsa.filesystem.getInfo(path)
        if info and info.type == 'directory' then
            sources(path, out)
        elseif name:match('%.lua$') then
            out[#out + 1] = path
        end
    end
    return out
end

function Module.run(self)
    local scene = Application.new(self.manager, 'stareShooter', { modules = {} })
    scene:load()
    self:check(
        scene:module('editor') == nil and scene.workspace == nil and scene.debugOverlay == nil,
        'A scene without modules has no editor, Workspace or Debug menu'
    )
    for _, key in ipairs({ 'f1', 'f2', 'f3', 'f4', 'f6', 'tab', 'w' }) do
        scene:keypressed(key)
        scene:keyreleased(key)
    end
    scene:textinput('a')
    scene:wheelmoved(0, 1)
    scene:update(1 / 60, 1 / 60)
    scene:draw()
    self:check(scene.showStats == false, 'Debug keys do nothing without the modules')
    scene:release()

    local full = Application.new(self.manager, 'stareShooter')
    full:load()
    self:check(
        full:module('editor') ~= nil and full:module('overlay') ~= nil and full.workspace ~= nil,
        'The default runtime installs the devtools modules'
    )
    full:release()

    -- The engine and the runtime never name the debug UI directly; only game/runtime/modules.lua does.
    local hits = {}
    for _, root in ipairs({ 'source/engine', 'game/runtime' }) do
        for _, path in ipairs(sources(root, {})) do
            if path ~= 'game/runtime/modules.lua' then
                local text = katsa.filesystem.read(path)
                if text and text:find('game.devtools', 1, true) then
                    hits[#hits + 1] = path
                end
            end
        end
    end
    self:check(#hits == 0, 'Nothing outside the module list requires game.devtools')
end

return Module

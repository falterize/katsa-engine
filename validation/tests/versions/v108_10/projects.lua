-- Projects, several shared:// folders, a scene folder outside the game source and the empty screen.
local Paths = require('source.engine.scenes.paths')
local Project = require('source.engine.scenes.project')
local Loader = require('source.engine.scenes.loader')
local Empty = require('source.engine.scenes.empty')

local Module = {}

function Module.run(self)
    local FS = katsa.filesystem
    self:check(
        Paths.resolve('shared://textures/engine/fallback/missing.png', { shared = { 'nowhere', 'assets' } })
            == 'assets/textures/engine/fallback/missing.png',
        'shared:// answers from the first listed folder that holds the file'
    )
    self:check(
        Paths.resolve('shared://x.png', { shared = { 'a', 'b' } }) == 'a/x.png',
        'a missing shared file resolves against the first folder'
    )
    self:check(Paths.resolve('shared://x.png') == 'assets/x.png', 'one folder or none still works')

    local project = Project.read({
        scenes = 'game/scenes',
        startScene = 'game/scenes/menu',
        sharedAssets = 'extra',
    })
    self:check(project.start == 'game/scenes/menu', 'A project names its start scene')
    self:check(project.shared[1] == 'assets' and project.shared[2] == 'extra', 'Engine assets come first')
    self:check(#project.scenes > 1, 'Every scene folder of the project is listed')
    self:check(Project.read(nil) == nil, 'No project outside a project run')

    local first = Loader.open(project.scenes[1].path)
    local second = Loader.open(project.scenes[2].path)
    self:check(first.id ~= second.id, 'Several scenes of one project open side by side')
    first:release()
    second:release()

    local folder = '../katsa-engine-examples/game/scenes/menu'
    local external = Loader.open(folder)
    self:check(external.id == 'menu', 'A scene folder outside the game source opens by path')
    external:release()

    local empty = Empty.new({}, { scenes = project.scenes, open = function() end })
    empty:keypressed('down')
    self:check(empty.selected == 2, 'The picker moves its selection')
end

return Module

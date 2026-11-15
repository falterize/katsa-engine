-- scene.root: the Game node holding the main World3D and the storage containers.
local Application = require('source.game.runtime.application')

local Module = {}

function Module.run(self)
    local scene = Application.new(self.manager, 'lights')
    scene:load()
    local root = scene.root
    self:check(root and root:isA('Game') and root.parent == nil, 'A scene has a Game node as its root')
    self:check(
        root:find('World3D') == scene.world.root and scene.world.root.parent == root,
        'The main World3D is an ordinary child of the Game node'
    )
    self:check(
        root:find('ReplicatedStorage') ~= nil and root:find('ServerStorage') ~= nil,
        'A single-player scene has both storage containers under the root'
    )
    self:check(
        root:findPath('World3D/World2D') == scene.ui and root:findPath('World3D/Nothing/X') == nil,
        'findPath follows names and reports a missing step as nil'
    )
    local folder = scene.world:create('Folder', { name = 'Stored' }, root:find('ServerStorage'))
    self:check(
        root:findPath('ServerStorage/Stored') == folder,
        'ServerStorage holds content in single-player'
    )
    local Storage = require('source.engine.net.replication.storage')
    local shared, server = Storage.install(scene.world, false)
    self:check(
        shared == root:find('ReplicatedStorage') and server == nil and root:find('ServerStorage') == nil,
        'A client of a remote server has no ServerStorage'
    )
    scene:release()
    self:check(root.destroyed, 'Releasing the scene destroys the Game node')
end

return Module

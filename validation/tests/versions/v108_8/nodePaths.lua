-- Node paths: find('A/B'), slashes inside names, findAncestor, isDescendantOf, getFullName, waitFor.
local Node = require('source.engine.nodes')

local Module = {}

local function make(name, parent)
    return Node.create('Folder', { name = name }, parent)
end

function Module.run(self)
    local root = Node.create('Root', { name = 'Root' })
    local map = make('Map', make('World3D', root))
    local house = make('House', map)
    local odd = make('Test/odd', map)
    local inner = make('Room', odd)
    local trailing = make('Slashed/', map)
    local after = make('after', trailing)
    self:check(
        root:find('World3D/Map/House') == house and root:find('World3D/Nothing/House') == nil,
        'find follows a path of child names and returns nil on a missing step'
    )
    self:check(
        root:find('Map/House') == nil and root:find('Map/House', true) == house,
        'A recursive path searches its first step in the whole subtree'
    )
    self:check(
        root:find('World3D/Map/Test/odd/Room') == inner and root:find('World3D/Map/Test/odd') == odd,
        'A slash inside a name is written as it is'
    )
    self:check(
        root:find('World3D/Map/Slashed//after') == after and root:find('World3D/Map/Slashed/') == trailing,
        'The last of several slashes separates the steps (a name may end with a slash)'
    )
    self:check(
        inner:getFullName() == 'Root/World3D/Map/Test/odd/Room'
            and root:find(inner:getFullName(root)) == inner,
        'getFullName gives a path that find accepts (relative to an ancestor)'
    )
    self:check(
        inner:findAncestor('Map') == map
            and inner:findAncestor({ className = 'Root' }) == root
            and inner:findAncestor('Room') == nil,
        'findAncestor matches a name or a filter'
    )
    self:check(
        inner:isDescendantOf(root) and not root:isDescendantOf(inner) and not inner:isDescendantOf(inner),
        'isDescendantOf checks the ancestors'
    )
    local got
    local handle = root:waitFor('World3D/Map/Late', function(node)
        got = node
    end)
    self:check(got == nil and not handle.done, 'waitFor waits while the path is missing')
    local late = make('Late', map)
    self:check(got == late and handle.done, 'waitFor calls back when a descendant completes the path')
    local at
    root:waitFor('World3D/Map/Late', function(node)
        at = node
    end)
    self:check(at == late, 'waitFor calls back at once when the node exists')
    local cancelled = false
    local second = root:waitFor('Never', function()
        cancelled = true
    end)
    second:cancel()
    make('Never', root)
    self:check(not cancelled, 'A cancelled wait never calls back')
    root:destroy()
end

return Module

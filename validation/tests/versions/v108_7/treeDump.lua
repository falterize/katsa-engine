-- Diagnostic: prints the Explorer rows of a scene (KATSA_SCENE).
local Previous = require('validation.tests.versions.v107.physics2D')
local Tests = setmetatable({}, { __index = Previous })
Tests.__index = Tests

function Tests.new(manager)
    return setmetatable(Previous.new(manager), Tests)
end

function Tests:update() end

function Tests:draw()
    self.frame = (self.frame or 0) + 1
    if self.frame == 1 then
        self.host = require('source.game.runtime.application').new(self.manager, os.getenv('KATSA_SCENE') or 'physics')
        self.host:load()
    end
    self.host:update(1 / 60, 1 / 60)
    self.host:draw()
    if self.frame == 30 then
        local ws = self.host.workspace or self.host.editor
        local Tree = require('source.engine.editor.tree.traversal')
        local rows = Tree.rows({ self.host.world.root }, {}, nil, '')
        for _, row in ipairs(rows) do
            print(('ROW %s%s (%s)'):format(('  '):rep(row.depth), row.node.name or '?', row.node.className or '?'))
        end
        katsa.event.quit()
    end
end

return Tests

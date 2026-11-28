local Node = require('../core.baseNode')

-- The 2D twin of Button3D. Put it under any node of a World2D (a UI node, a Node2D, a Body2D,
-- a plain Node) and that node becomes clickable without a look of its own: with `includeDescendants`
-- every UI node below the target counts, so one Button2D on a Node2D or a physics body covers its
-- whole picture. A text button is a Label with a Button2D inside. Same settings and signals as
-- Button3D (`enabled`, `priority`, `includeDescendants`; press, release, click, cancel).
local Class = Node.define('Button2D', 'Node')

require('../../components.ordering.priority').describe(Class)

function Class.initialize(self)
    require('source.engine.components.ordering.priority').normalize(self)
    self.enabled = self.enabled ~= false
    self.includeDescendants = self.includeDescendants ~= false
end

function Class.mount(context, properties, parent)
    assert(parent, 'Button2D requires a parent: the node it makes clickable')
    local node = Node.new('Button2D', properties, parent)
    -- The target finds its button through this field when a pointer lands on it or below it.
    rawset(parent, '_button2D', node)
    node:onDestroy(function()
        if rawget(parent, '_button2D') == node then
            rawset(parent, '_button2D', nil)
        end
    end)
    return node
end

function Class:getTarget()
    return self.parent
end

-- A Button2D answers pointer hits only while it is on and its target is visible.
function Class:canActivate()
    local target = self.parent
    return self.enabled and target and target.visible ~= false
end

require('../../components.interaction.pointerVerbs').install(Class)

return Class

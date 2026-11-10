local Array = require('../../math.array')
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
local PropertyChanges = require('./propertyChanges')
local Parenting = require('./parenting')
local Hierarchy = require('./hierarchy')
local Signals = require('./signals')
local Lifecycle = require('./lifecycle')
local Attributes = require('./attributes')

local Node = {
    classes = {},
    aliases = {
        EnvironmentLighting = 'Environment',
        EnviromentLighting = 'Environment',
        ['UIGradient'] = 'Ramp',
        ['ScreenUI'] = 'World2D',
        ['RigidBody'] = 'Body3D',
        ['Body'] = 'Body3D',
        ['Collider'] = 'Collider3D',
        ['Camera'] = 'Camera3D',
        ['Attachment'] = 'Attachment3D',
        ['Mesh'] = 'Mesh3D',
        ['World'] = 'World3D',
        ['PointLight'] = 'PointLight3D',
        ['SpotLight'] = 'SpotLight3D',
        ['DirectionalLight'] = 'DirectionalLight3D',
        ['ClickDetector'] = 'ClickDetector3D',
        ['Billboard'] = 'BillboardUI',
        ['SurfaceUI3D'] = 'SurfaceUI',
        ['Billboard3D'] = 'BillboardUI',
        ['Decal'] = 'Decal3D',
    },
}
local ClassPolicy = require('./classPolicy')
local inheritInitializers, propertyAliases = ClassPolicy.initialize, ClassPolicy.propertyAliases
require('./classDefinition').install(Node)

function Node.getClass(name, context)
    name = Node.aliases[name] or name
    return assert(
        context and context.nodeTypes and context.nodeTypes[name] or Node.classes[name],
        'Unknown node class: ' .. tostring(name) .. '. Define the class before creating instances.'
    )
end

function Node.create(className, properties, parent, context)
    local class = Node.getClass(className, context)
    properties = properties or {}
    properties._registeredClass = class
    properties.className = className
    if class.mount then
        local wasNode = properties._node
        local ok, result = pcall(class.mount, context, properties, parent)
        if not ok then
            if not wasNode and properties._node then
                pcall(properties.destroy, properties)
            end
            error(result, 0)
        end
        return result
    end
    return Node.new(className, properties, parent)
end

function Node:setProcess(enabled)
    local tree = self._tree or self._processTree
    assert(tree, 'setProcess requires a node registered with a World3D NodeTree')
    tree:setProcess(self, enabled)
    return self
end
Node.connect, Node.emit = Signals.connect, Signals.emit

local function unlink(node)
    local parent = rawget(node, '_parent')
    if parent then
        for i, child in ipairs(parent.children) do
            if child == node then
                table.remove(parent.children, i)
                break
            end
        end
    end
end

function Node.adopt(node, className)
    if rawget(node, '_node') then
        return node
    end
    for alias, key in pairs(propertyAliases) do
        local value = rawget(node, alias)
        if value ~= nil then
            rawset(node, key, value)
            rawset(node, alias, nil)
        end
    end
    node._zIndexAuthored = rawget(node, 'zIndex') ~= nil
    local parent = rawget(node, 'parent')
    node.parent = nil
    node._node, node.className =
        true,
        (rawget(node, '_registeredClass') and node._registeredClass.name) or className or 'Node'
    node.children = node.children or {}
    node._cleanup = {}
    local class = rawget(node, '_registeredClass') or Node.getClass(node.className)
    rawset(node, '_registeredClass', nil)
    node._class = class
    node.className = class.name
    setmetatable(node, class.instanceMetatable)
    local ok, message = pcall(function()
        inheritInitializers(class, node)
        require('source.engine.math.valueTypes').initialize(node)
        PropertyChanges.initialize(node)
    end)
    if not ok then
        pcall(node.destroy, node)
        error(message, 0)
    end
    if parent then
        node:setParent(parent)
    end
    return node
end

function Node.new(className, properties, parent)
    local node = Node.adopt(properties or {}, className)
    node.name = node.name or className
    local ok, message = pcall(node.setParent, node, parent)
    if not ok then
        pcall(node.destroy, node)
        error(message, 0)
    end
    return node
end

function Node:setParent(parent)
    assert(not self.destroyed, 'Cannot reparent a destroyed node')
    assert(
        parent == nil or (Array.is(parent) and parent._node and not parent.destroyed),
        'Parent must be a live Node instance'
    )
    Parenting.validate(self, parent)
    if self.parent == parent then
        return self
    end
    local oldParent = self.parent
    unlink(self)
    rawset(self, '_parent', parent)
    PropertyChanges.touch(self)
    self._parentRevision = nil
    if parent then
        assert(parent.children and not parent.destroyed, 'Parent must be a live node or UI root')
        parent.children[#parent.children + 1] = self
    end
    Hierarchy.bind(
        self,
        parent and (parent._tree or parent._nodeTree),
        parent and (parent._sceneWorld or parent._world)
    )
    if self.ui then
        self.ui:invalidate()
    end
    self:emit('parentChanged', parent, oldParent)
    return self
end

function Node:find(name, recursive)
    for _, child in ipairs(self.children) do
        if child.name == name then
            return child
        end
        if recursive then
            local found = child:find(name, true)
            if found then
                return found
            end
        end
    end
end

function Node:isA(className)
    className = Node.aliases[className] or className
    return self._class._types[className] == true
end
Node.onDestroy, Node.destroy = Lifecycle.onDestroy, Lifecycle.destroy
Node.trackConnection, Node.own = Lifecycle.trackConnection, Lifecycle.own
for _, key in ipairs({
    'getChildren',
    'getDescendants',
    'findAll',
    'findByType',
    'findByTag',
    'addTag',
    'removeTag',
    'hasTag',
    'getTags',
}) do
    Node[key] = Hierarchy[key]
end

Node.setAttribute, Node.getAttribute = Attributes.set, Attributes.get
Node.getAttributes, Node.getAttributeNames = Attributes.all, Attributes.names
Node.setAttributeReference, Node.onAttributeChanged = Attributes.setReference, Attributes.onChanged
Node.isAttributeReference, Node.attributeView = Attributes.isReference, Attributes.view

-- Deep copy of this node and its descendants; `properties` overrides the copy's fields
-- (for example { Name = 'Copy' }) and `parent` defaults to this node's parent.
function Node:clone(properties, parent)
    return require('source.engine.nodes.core.clone').node(self, properties, parent)
end

function Node:attachment(properties)
    return Node.new('Attachment3D', properties or {}, self)
end
local BaseNode = Node.define('Node')
for _, key in ipairs({
    'setParent',
    'find',
    'isA',
    'onDestroy',
    'destroy',
    'attachment',
    'clone',
    'connect',
    'emit',
    'setProcess',
    'trackConnection',
    'own',
    'getChildren',
    'getDescendants',
    'findAll',
    'findByType',
    'findByTag',
    'addTag',
    'removeTag',
    'hasTag',
    'getTags',
    'setAttribute',
    'getAttribute',
    'getAttributes',
    'getAttributeNames',
    'setAttributeReference',
    'onAttributeChanged',
    'isAttributeReference',
    'attributeView',
}) do
    BaseNode[key] = Node[key]
end

return Node

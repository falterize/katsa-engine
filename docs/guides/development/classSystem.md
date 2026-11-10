# Node classes and naming

Public properties, methods and compound filenames use lowerCamelCase; class names use PascalCase; namespaces and directories use lowercase. This follows the v38 convention. Code, comments and documentation are English.

`source.engine.nodes` registers the built-in classes. `Node.define(name, base)` defines a class with shared methods and inherited initialize hooks. `Node.create` mounts resource-backed classes through their owner; `Node.new` creates lightweight nodes. Use World3D:create for world-owned meshes, lights and cameras, and UI:create for UI widgets.

World3D organizes top-level nodes under Geometry, Lights, Cameras, Billboards and Scripts. Explicit parent arguments preserve attachments and custom hierarchy. Folder contributes no transform. Node3D inherits the nearest spatial ancestor; scale supplies spatial scale while size supplies geometry dimensions, and rotation uses degrees.

Call node:setProcess(true) only for nodes with update(dt) that are attached to a World3D NodeTree. Registered callbacks receive scaled simulation time. Connections support disconnect; destruction is recursive and reentrant-safe and releases subscriptions and owner indexes. Resource-owned nodes cannot move between different Worlds.

UI widgets require an explicit parent under a CanvasGroup or their BillboardUI owner. Raw ScreenUI roots accept CanvasGroup only. Reparenting enforces this policy as well as cycle protection.

For scene/game custom types use world:registerNodeType(name,definition), not the
global Node.define registry. Each World3D holds independent names and property
descriptors; World3D:create registers update processing automatically for these
types. See the reusable game BouncePad module and its explicit `register` entry point.

## Example: a custom node type

```lua
-- nodes/bouncePad.lua: one table is the whole definition.
local BouncePad = {
    base = 'Mesh3D',
    properties = { force = { default = 12, min = 0, hint = 'Upward speed given to a body.' } },
}

function BouncePad.initialize(self)
    self.color = self.color or { 0.2, 0.8, 0.4, 1 }
end

function BouncePad.register(world)
    return world:registerNodeType('BouncePad', BouncePad)
end

-- In the scene:
BouncePad.register(world)
local pad = world:create('BouncePad', { position = { 0, 0.5, 0 }, force = 20 })
local connection = pad:connect('destroying', function() print('pad removed') end)
connection:disconnect()      -- every connect returns a connection with :disconnect()
```

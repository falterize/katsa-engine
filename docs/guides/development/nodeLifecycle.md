# Nodes, hierarchy and lifecycle

## Ownership and parents

Create engine nodes through `world:create(className, properties, parent)` so resource systems can mount them. Omitted World3D parents resolve to the existing category Folder. UI creation must resolve a compatible UI service and parent; use the owning UI service to create widgets. `Node.new` creates plain/class instances; it is not a substitute for mounting a Mesh3D into a renderer or a sound into an audio service.

Every node exposes `parent`; roots may use nil. Assigning `node.parent` and calling `node:setParent(parent)` are equivalent. Parenting validates cycles, the entire moving subtree, World3D identity, UI ownership, spatial/UI boundaries and World3D-space physics constraints before modifying the live tree. Local transforms are preserved. World3D-pose-preserving reparenting belongs to the separate transform stage.

A node attached to a World3D acquires that scene identity, including plain script nodes and Folders. Detachment retains identity. Reattachment to the same World3D resumes processing; migration to another World3D requires creating a new instance. This closes the old generic-node migration gap. UI-owned nodes retain their UI service's stricter parent policy. Mutating `children`, `_parent` or other internal fields directly is unsupported.

## Queries and tags

```lua
local actor = world:create('Node3D', { name = 'Actor' })
actor:addTag('enemy'):addTag('interactable')
local socket = actor:attachment({ name = 'Head', position = { 0, 12, 0 } })
socket:addTag('socket')

local children = actor:getChildren()
local descendants = world.root:getDescendants()
local head = actor:find('Head', true)
local attachment = actor:findByType('Attachment3D', true)
local enemy = world.root:findByTag('enemy', true)
local matches = world.root:findAll({ className = 'Node3D', tag = 'enemy' }, true)
actor:removeTag('interactable')
local tags = actor:getTags()
```

Query results are independent array snapshots. Descendants use child insertion order and depth-first preorder. Type matching includes base classes through `isA`; filters combine with AND. Recursive queries are opt-in except `getDescendants`. Tags are nonempty strings; `getTags` returns sorted strings. Queries allocate only when requested, not per frame.

## Initialization and processing

1. The class instance and cleanup storage are created.
2. `initialize(self)` runs once on each base class, from base to derived. A failure cleans resources registered so far and propagates the original error.
3. Valid parenting/mounting occurs. The relevant World3D resource system completes registration.
4. Scene-owned custom nodes created through `world:create` automatically register their `update(dt)` processing. For lower-level/global script instances, call `node:setProcess(true)` after attachment. On its first positive-time update, an optional `start(self)` runs once, followed by the `started` signal and then `update(self, dt)`. The most-derived/inherited start method is called; overrides can invoke their base explicitly.
5. Later updates reuse the registered update method. Re-register if replacing that method at runtime. Detaching, disabling processing or setting dt <= 0 skips updates. Reattachment to the same tree does not repeat start.
6. Destroy closes the node and its descendants and clears their records/resources.

Newly registered nodes wait until the next NodeTree update. Nodes destroyed/detached/disabled before their turn are skipped. Changes to unrelated nodes are immediately visible to subsequent callbacks. NodeTree caches membership during hierarchy mutations; it does not climb each processed node's parents every frame. `NodeTree:update` is not reentrant. A callback error does not strand iteration bookkeeping; remaining eligible records are processed and the first error is propagated. A failed start disables processing and rejects re-enabling the incomplete script; dispose/recreate that node after fixing the error.

## Events and owned cleanup

```lua
local receiver = world:create('Node', { name = 'Receiver' })
local connection = receiver:connect('ping', function(value)
    print(value)
end)
receiver:emit('ping', 42)
connection:disconnect()

-- A node can own its subscriptions to other nodes/services.
actor:trackConnection(receiver:connect('ping', function(value)
    print(actor.name, value)
end))
actor:onDestroy(function()
    print('Actor cleanup')
end)
-- For an exclusive resource that actor alone owns:
-- actor:own(katsa.graphics.newCanvas(64, 64))
```

Connections added during an emission wait until its next emission; disconnections take effect immediately. Nested emission has its own starting listener count. Dead records are compacted at safe boundaries. Destroying an emitter disconnects remaining callbacks. Listener errors allow other still-connected listeners to finish before propagating the first error.

`trackConnection` owns external disconnectable subscriptions. `own` owns an exclusive resource with `release`; do not register shared cached resources here, and do not also put the same resource in the scene Resources owner. `onDestroy` cleanup runs in reverse registration order. These helpers reject closing nodes.

Destruction is idempotent and reentrant-safe: the node is marked closing and unlinked before `destroying` is emitted; descendants are destroyed, connections are disconnected, then registered cleanup runs. All cleanup is attempted even if callbacks fail. Game scene shutdown and the shared resource scope also continue through their remaining release operations after a subsystem error. The first failure is rethrown afterward. Closing descendants cannot escape by reparenting. During `destroying`, `node.parent` is now nil; capture the former parent before calling destroy if it is needed. This differs from the earlier ordering and prevents child callbacks from recursively trapping ancestor destruction.

## Physical contacts

Node changes are immediate at the Lua hierarchy level. Physical body insertion/removal requested during an Oimo step or its queued removal callbacks is deferred until the solver has finished that step. Closing bodies suppress further user contact notifications. Creating and destroying a body in one contact leaves no backend body. Scene transitions continue to use `manager:requestSwitch`, not synchronous scene replacement inside a solver callback. Other collider/joint/type edits remain subject to the existing physics API and are not a general transactional physics editor.

## Validation

The headless suite checks query snapshots, tags, scene ownership, initialization failures, signals/errors/reentrancy, cleanup, processing mutations, real Oimo contact removal/insertion and stable light selection. The Lua 5.3 compatibility bridge is test-only; production remains katsa's LuaJIT. Graphics/Android tests require the actual target runtime.

Spatial nodes in v45 also support `setParent(parent, {keepWorldTransform=true})`.
The new local TRS is validated before hierarchy mutation. Ordinary parent assignment
still preserves local pose; see `spatialTransforms.md` for shear/body constraints.

The [node authoring reference](nodeAuthoring.md) explains adopt, mount, all common
instance/spatial methods, built-in type methods and a tested scene-owned Spinner.
Node `enabled = false` suppresses behavior updates; use `setProcess(false)` when
the first start callback must also remain unscheduled.

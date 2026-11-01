local Node = require('source.engine.nodes')
local Tree = require('source.engine.nodes.core.nodeTree')
return function(test)
    local function check(ok, msg)
        test:check(ok, msg)
    end
    local worldA, worldB = {}, {}
    local a = Node.new('World3D', { _world = worldA })
    local b = Node.new('World3D', { _world = worldB })
    local tree = Tree.new(a)
    local folder = Node.new('Folder', { name = 'Actors' }, a)
    local one = Node.new('Node3D', { name = 'Actor' }, folder)
    local two = Node.new('Attachment3D', { name = 'Socket' }, one)
    one:addTag('enemy'):addTag('interactive')
    two:addTag('socket')
    local children = folder:getChildren()
    children[1] = nil
    check(folder.children[1] == one, 'Child queries return independent snapshots')
    local descendants = folder:getDescendants()
    check(descendants[1] == one and descendants[2] == two, 'Descendants use deterministic preorder')
    check(
        folder:findByType('Node3D', true) == one and folder:findByType('Attachment3D', true) == two,
        'Type queries respect class inheritance'
    )
    check(folder:findByTag('socket', true) == two, 'Tag query follows descendants')
    check(
        #folder:findAll({ className = 'Node3D', tag = 'enemy' }, true) == 1,
        'Combined query filters work'
    )
    check(
        one:getTags()[1] == 'enemy' and one:hasTag('interactive'),
        'Tags are independent and deterministic'
    )
    one:removeTag('enemy')
    check(not one:hasTag('enemy'), 'Tags can be removed')
    local ok = pcall(folder.setParent, folder, b)
    check(not ok and folder.parent == a, 'Generic nodes cannot cross scene ownership')
    folder.parent = nil
    check(
        one._tree == nil and two._tree == nil,
        'Detach removes processing membership from descendants'
    )
    check(not pcall(folder.setParent, folder, b), 'Detached generic subtrees retain scene identity')
    folder.parent = a
    check(
        one._tree == tree and two._tree == tree,
        'Reattach restores subtree processing membership'
    )
    local original, late, skipped = 0, 0, 0
    local connection
    one:connect('event', function()
        original = original + 1
        if original == 1 then
            connection:disconnect()
            one:connect('event', function()
                late = late + 1
            end)
        end
    end)
    connection = one:connect('event', function()
        skipped = skipped + 1
    end)
    one:emit('event')
    check(original == 1 and skipped == 0 and late == 0, 'Signal mutation uses emission boundaries')
    one:emit('event')
    check(late == 1, 'New connections run on the next emission')
    for i = 1, 100 do
        local c = one:connect('transient', function() end)
        c:disconnect()
    end
    one:emit('transient')
    check(#one._signals.transient == 0, 'Disconnected signal records are compacted')
    local nested = 0
    one:connect('nested', function()
        nested = nested + 1
        if nested == 1 then
            one:emit('nested')
        end
    end)
    one:emit('nested')
    check(nested == 2, 'Nested emissions remain safe')
    local afterError = 0
    one:connect('error', function()
        error('expected signal failure')
    end)
    one:connect('error', function()
        afterError = afterError + 1
    end)
    check(
        not pcall(one.emit, one, 'error') and afterError == 1 and one._signals.error.depth == 0,
        'Signal errors propagate after other listeners and restore bookkeeping'
    )
    local external = Node.new('Node', {})
    local tracked = one:trackConnection(external:connect('external', function() end))
    local released = 0
    one:own({
        release = function()
            released = released + 1
        end,
    })
    local cleanup = 0
    one:onDestroy(function()
        cleanup = cleanup + 1
    end)
    one:onDestroy(function()
        error('expected cleanup failure')
    end)
    check(
        not pcall(one.destroy, one) and one.destroyed and two.destroyed,
        'Destroy completes the subtree before propagating callback errors'
    )
    check(
        cleanup == 1 and released == 1 and not tracked.connected,
        'Resources and external connections clean up despite errors'
    )
    check(#folder.children == 0, 'Destroy unlinks the node from the live tree')
    one:destroy()
    check(released == 1, 'Repeated destruction does not release resources twice')
    local parent = Node.new('Folder', {}, a)
    local child = Node.new('Node', {}, parent)
    child:connect('destroying', function()
        parent:destroy()
    end)
    child:destroy()
    check(
        parent.destroyed and child.destroyed,
        'Destroying an ancestor from a child callback terminates safely'
    )
    local Process = Node.classes.TestLifecycleProcess or Node.define('TestLifecycleProcess', 'Node')

    function Process:start()
        self.starts = (self.starts or 0) + 1
    end

    function Process:update(dt)
        self.ticks = (self.ticks or 0) + 1
        if self.action then
            self:action(dt)
        end
    end
    local p = Node.new('TestLifecycleProcess', {}, folder)
    p:setProcess(true)
    local started = 0
    p:connect('started', function()
        started = started + 1
    end)
    tree:update(0)
    check(not p.starts, 'Zero simulation time does not start processing')
    tree:update(1)
    tree:update(1)
    check(
        p.starts == 1 and started == 1 and p.ticks == 2,
        'Start hook and event run once before the first update'
    )
    local fresh
    p.action = function(self)
        if not fresh then
            fresh = Node.new('TestLifecycleProcess', {}, folder)
            fresh:setProcess(true)
        end
    end
    tree:update(1)
    check(not fresh.ticks, 'Nodes registered during update wait until the next update')
    tree:update(1)
    check(fresh.ticks == 1, 'Deferred registration runs on the next update')
    p.parent = nil
    tree:update(1)
    check(p.ticks == 4, 'Detached processed nodes skip updates')
    p.parent = folder
    tree:update(1)
    check(p.ticks == 5 and p.starts == 1, 'Reattached nodes resume without restarting')
    p:setProcess(false)
    tree:update(1)
    check(p.ticks == 5, 'Disabled processing skips updates')
    p:setProcess(true)
    p.action = function()
        fresh:destroy()
    end
    tree:update(1)
    check(
        fresh.destroyed and #tree.records == 1,
        'Destruction during update removes pending processed nodes'
    )
    p.action = function(self)
        self:setProcess(false)
        error('expected update failure')
    end
    check(
        not pcall(tree.update, tree, 1) and not tree.updating,
        'Update errors restore iteration state'
    )
    tree:update(1)
    local initOrder = {}
    local Base = Node.classes.TestInitBase or Node.define('TestInitBase', 'Node')
    local Derived = Node.classes.TestInitDerived or Node.define('TestInitDerived', 'TestInitBase')
    Base.initialize = function()
        initOrder[#initOrder + 1] = 'base'
    end
    Derived.initialize = function()
        initOrder[#initOrder + 1] = 'derived'
    end
    Node.new('TestInitDerived', {}, folder)
    check(
        initOrder[1] == 'base' and initOrder[2] == 'derived' and #initOrder == 2,
        'Initializers run once from base to derived'
    )
    local Failed = Node.classes.TestFailedInit or Node.define('TestFailedInit', 'Node')
    local failedRelease = 0
    Failed.initialize = function(self)
        self:own({
            release = function()
                failedRelease = failedRelease + 1
            end,
        })
        error('expected initializer failure')
    end
    local failed = {}
    check(
        not pcall(Node.new, 'TestFailedInit', failed, folder)
            and failed.destroyed
            and failedRelease == 1,
        'Initializer failure cleans resources before propagating'
    )
    local Mount = Node.classes.TestFailedMount or Node.define('TestFailedMount', 'Node')
    Mount.mount = function(_, properties, parent)
        Node.adopt(properties, 'TestFailedMount')
        properties.parent = parent
        properties:own({
            release = function()
                failedRelease = failedRelease + 1
            end,
        })
        error('expected mount failure')
    end
    local mounted = {}
    check(
        not pcall(Node.create, 'TestFailedMount', mounted, folder, {})
            and mounted.destroyed
            and mounted.parent == nil
            and failedRelease == 2,
        'Mount failure cleans the partially created node'
    )
    local emitter = Node.new('Node', {}, folder)
    local unwanted = 0
    emitter:connect('closing', function()
        emitter:destroy()
    end)
    emitter:connect('closing', function()
        unwanted = unwanted + 1
    end)
    emitter:emit('closing')
    check(
        emitter.destroyed and unwanted == 0,
        'Destroy during emission cancels remaining listeners'
    )
    local closing = Node.new('Folder', {}, a)
    local escape = Node.new('Node', {}, closing)
    local escaped
    closing:connect('destroying', function()
        escaped = pcall(escape.setParent, escape, folder)
    end)
    closing:destroy()
    check(
        not escaped and escape.destroyed,
        'Closing descendants cannot escape their owner during destruction'
    )
    p.parent = nil
    p:setProcess(false)
    check(
        not tree.byNode[p].enabled,
        'Detached nodes can disable their existing process registration'
    )
    p.parent = folder
    p:setProcess(true)
    p.action = function()
        tree:update(1)
    end
    check(
        not pcall(tree.update, tree, 1) and not tree.updating,
        'Reentrant updates fail without corrupting the tree'
    )
    p:setProcess(false)
    local suicide = Node.new('TestLifecycleProcess', {}, folder)
    suicide.start = function(self)
        self:destroy()
    end
    suicide:setProcess(true)
    tree:update(1)
    check(suicide.destroyed and not suicide.ticks, 'Destruction in start prevents the first update')
    local deferred = Node.new('TestLifecycleProcess', {}, folder)
    p:setProcess(true)
    p.action = function()
        deferred.parent = nil
    end
    deferred:setProcess(true)
    tree:update(1)
    check(
        deferred.parent == nil and not deferred.ticks,
        'Earlier updates can detach later nodes before their turn'
    )
    deferred:destroy()
    p:setProcess(false)
    local failedStart = Node.new('TestLifecycleProcess', {}, folder)
    failedStart.start = function()
        error('expected start failure')
    end
    failedStart:setProcess(true)
    check(
        not pcall(tree.update, tree, 1)
            and not tree.byNode[failedStart].enabled
            and not pcall(failedStart.setProcess, failedStart, true),
        'Failed start disables the incomplete script and requires recreation'
    )
    tree:update(1)
    check(not failedStart.ticks, 'Failed-start nodes never receive an update')
    local UI = require('source.engine.ui')
    local uiA, uiB = UI.new(100, 100, {}), UI.new(100, 100, {})
    local container = Node.new('Folder', {}, uiA.content)
    local widget = uiA:create('Frame', { width = 10, height = 10 }, container)
    check(
        not pcall(container.setParent, container, uiB.content) and widget.parent == container,
        'Folder transfers cannot bypass nested UI-service ownership'
    )
    check(
        not pcall(container.setParent, container, nil) and container.parent == uiA.content,
        'UI descendants cannot lose their required root through an ancestor detach'
    )
    uiA:release()
    uiB:release()
    local resources = require('source.engine.core.resources').new()
    local freed = 0
    resources:own({
        release = function()
            freed = freed + 1
        end,
    })
    resources:own({
        release = function()
            error('expected resource release failure')
        end,
    })
    check(
        not pcall(resources.release, resources) and freed == 1 and #resources.owned == 0,
        'Resource scope attempts every release despite an individual failure'
    )
    local actions = 0
    local Cleanup = require('source.engine.core.cleanup')
    check(not pcall(Cleanup.run, {
        function()
            error('expected shutdown failure')
        end,
        function()
            actions = actions + 1
        end,
    }) and actions == 1, 'Scene shutdown actions continue after a subsystem error')
    a:destroy()
    tree:release()
    b:destroy()
    external:destroy()
    check(p.destroyed and next(tree.byNode) == nil, 'Scene shutdown releases processing records')
end

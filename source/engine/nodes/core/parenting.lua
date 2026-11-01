local ipairs = require('source.engine.math.array').ipairs
-- Validate the proposed tree before unlinking anything. Traversal occurs only
-- during parenting, never in the render or simulation frame loop.
local Parenting = {}

local function destinationWorld(parent)
    while parent do
        if parent._world or parent._sceneWorld then
            return parent._world or parent._sceneWorld
        end
        parent = parent.parent
    end
end

local function validateSubtree(node, parent, world, screenHierarchy, uiAnchor)
    assert(not node.destroyed and not node._destroying, 'Cannot move a destroying subtree')
    if node:isA('World3D') and node._worldBoundary then
        assert(
            parent and parent:isA('ViewportFrame'),
            'An independent World3D must belong to ViewportFrame'
        )
        assert(
            not world or world == node._world.hostWorld,
            'Viewport worlds cannot move between scene scopes'
        )
        assert(
            not parent:getWorld() or parent:getWorld() == node._world,
            'ViewportFrame already owns a World3D'
        )
        return
    end
    if node:isA('Environment') then
        assert(
            parent and parent == node._environmentOwner,
            'Environment must stay inside its owning world'
        )
    end
    assert(
        not world
            or (not node._world or node._world == world)
                and (not node._sceneWorld or node._sceneWorld == world),
        'Resource-owned nodes cannot move between Worlds; recreate them in the destination scene'
    )
    if node:isA('SurfaceUI') or node:isA('Decal3D') then
        assert(
            (node.adornee or parent)
                and (node.adornee or parent):isA('Node3D')
                and not (node.adornee or parent):isA('BillboardUI'),
            'Surfaces require a Mesh3D, Attachment3D or Node3D parent'
        )
    end
    if node:isA('ClickDetector3D') then
        local target = node.adornee or node._requestedAdornee or parent
        assert(
            target and target:isA('Mesh3D'),
            'ClickDetector3D requires a Mesh3D Parent or Adornee'
        )
    end
    if node:isA('Collider2D') then
        assert(parent and parent:isA('Body2D'), 'Collider2D requires a Body2D parent')
    end
    if node:isA('Node2D') or node:isA('Constraint2D') then
        local owner = parent
        while owner and not owner:isA('World2D') do
            assert(not owner:isA('UINode'), 'Spatial 2D nodes cannot belong to widgets')
            owner = owner.parent
        end
        assert(
            owner and (not node._plane or node._plane == owner),
            '2D nodes must retain their World2D owner'
        )
        assert(
            not node.physics or node.physics == owner.physics2D,
            'Constraints cannot cross 2D worlds'
        )
    end
    if node:isA('Collider3D') then
        assert(parent and parent:isA('Body3D'), 'Collider3D requires a Body3D parent')
    end
    if node:isA('SurfaceAppearance3D') then
        assert(parent and parent:isA('Mesh3D'), 'SurfaceAppearance3D must remain inside Mesh3D')
    end
    if node:isA('SoundEffect') then
        assert(
            parent and (parent:isA('Sound') or parent:isA('SoundGroup')),
            'Sound effects require a Sound or SoundGroup parent'
        )
    end
    if node._audio then
        local owner = parent
        while owner do
            assert(
                not owner._audio or owner._audio == node._audio,
                'Audio nodes cannot cross scene scopes'
            )
            owner = owner.parent
        end
    end
    if node.ui and node:isA('UINode') then
        node.ui:validateParent(node, parent)
        assert(
            uiAnchor
                and (
                    uiAnchor == node.ui
                    or uiAnchor == node.ui.owner
                    or uiAnchor.ui == node.ui
                    or uiAnchor._plane == node.ui
                ),
            'UI descendants must retain their UI owner in the proposed hierarchy'
        )
    end
    if node:isA('World2D') then
        assert(
            parent and parent:isA('World3D') or node.owner and parent == node.owner,
            'World2D requires a World3D owner'
        )
    end
    if node:isA('Node3D') and not node:isA('BillboardUI') then
        assert(not screenHierarchy, 'Spatial nodes cannot belong to a screen widget hierarchy')
        local owner = parent
        while owner do
            if owner:isA('World3D') then
                break
            end
            assert(
                not owner:isA('UINode') and not owner:isA('ScreenUI'),
                'Spatial nodes cannot belong to a screen widget hierarchy'
            )
            owner = owner.parent
        end
    end
    if node.body and not node._independentBody then
        local owner = parent
        while owner and owner:isA('Folder') do
            owner = owner.parent
        end
        assert(
            not owner or owner:isA('World3D'),
            'Rigid bodies require World3D space; organizational Folders are allowed'
        )
    end
    if
        node:isA('CanvasGroup')
        or node:isA('BillboardUI')
        or node:isA('ScreenUI')
        or node:isA('Node2D')
    then
        uiAnchor = node
    end
    for _, child in ipairs(node.children) do
        validateSubtree(child, node, world, screenHierarchy, uiAnchor)
    end
end

function Parenting.validate(node, parent)
    local current = node
    while current do
        assert(not current._destroying, 'Cannot reparent a closing subtree')
        current = current.parent
    end
    assert(
        not node:isA('World3D')
            or parent == nil
            or node._worldBoundary and parent:isA('ViewportFrame'),
        'World3D is a root or an independent ViewportFrame child'
    )
    local owner = parent
    while owner do
        assert(owner ~= node, 'Node hierarchy cannot contain a cycle')
        assert(not owner._destroying, 'Parent must not be destroying')
        owner = owner.parent
    end
    -- A body's Folder ancestors are evaluated against the proposed chain.
    -- Check them without mutating the live parent pointers.
    local function checkBodies(item, foldersOnly)
        if item.body and not item._independentBody and foldersOnly then
            local ancestor = parent
            while ancestor and ancestor:isA('Folder') do
                ancestor = ancestor.parent
            end
            assert(
                not ancestor or ancestor:isA('World3D'),
                'Rigid bodies require World3D space; organizational Folders are allowed'
            )
        end
        for _, child in ipairs(item.children) do
            checkBodies(child, foldersOnly and item:isA('Folder'))
        end
    end
    checkBodies(node, true)
    local screenHierarchy = false
    owner = parent
    while owner do
        if owner:isA('World3D') then
            break
        end
        screenHierarchy = screenHierarchy or owner:isA('UINode') or owner:isA('ScreenUI')
        owner = owner.parent
    end
    local uiAnchor
    owner = parent
    while owner do
        if
            owner:isA('CanvasGroup')
            or owner:isA('BillboardUI')
            or owner:isA('ScreenUI')
            or owner:isA('Node2D')
        then
            uiAnchor = owner
            break
        end
        owner = owner.parent
    end
    validateSubtree(node, parent, destinationWorld(parent), screenHierarchy, uiAnchor)
end

return Parenting

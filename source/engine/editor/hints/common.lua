-- Inspector descriptions shared by every class that has the property. A class entry in the
-- category files wins over these. Editor text only.
local keys = {
    absoluteCanvasSize = 'Resolved canvas extent in logical pixels, including automatic content '
        .. 'bounds.',
    absoluteWindowSize = 'Resolved viewport dimensions after scrollbar insets, in logical pixels.',
    adornee = 'Independent spatial support in this World3D. Parent still owns the node. Removed '
        .. 'support hides it until a new reference or explicit None is chosen.',
    angularDamping = 'Angular velocity decay in 1/second (>=0). 0 preserves spin; 2 makes '
        .. 'rotation settle quickly. Independent of friction.',
    automaticCanvasSize = 'Extend the authored canvas minimum to visible descendant bounds on '
        .. 'None, X, Y or XY axes.',
    automaticLength = 'Measure visible non-modifier descendants after layout. Clipped '
        .. 'descendants contribute only their container. Cached until resolved geometry changes.',
    bones = 'Show skeletons in this World3D. Individual Animator.debugEnabled can also enable '
        .. 'bone lines.',
    brightness = 'Nonnegative RGB multiplier. 1 preserves content brightness. Does not change '
        .. 'alpha, emit light or generate bloom.',
    canvasPixelsPerUnit = 'Logical canvas pixels per world unit in World3D mode and Tiles. '
        .. 'Screen mode uses logical Size pixels directly.',
    canvasPosition = 'Logical-pixel scroll offset, clamped to the resolved canvas and viewport.',
    canvasSize = 'UDim2 relative to resolved Size. Screen base uses logical pixels; World3D '
        .. 'base uses world dimensions times canvasPixelsPerUnit. GPU limits may proportionally '
        .. 'reduce the canvas.',
    castShadow = 'Writes this node into the shadow maps as alpha tested geometry.',
    clip = 'Clip descendant UI to this container rectangle. False allows descendants outside '
        .. 'its bounds; ancestor clips still apply.',
    depthPrepass = 'Automatic early depth for dense, fully opaque built-in mesh scenes with 4+ '
        .. 'lights. Skips unknown alpha, custom materials and MSAA; preserves normal shading and '
        .. 'depth ordering.',
    enabled = 'Suspend input and material time in this UI branch; modifiers stop applying. '
        .. 'BillboardUI retains its last canvas. Visible content remains displayed.',
    extentsOffset = 'Panel displacement along camera Right/Up/Forward, in half dimensions of '
        .. 'the camera-aligned support bounds. Does not move the anchor.',
    extentsOffsetWorldSpace = 'Panel displacement along world X/Y/Z, in half dimensions of '
        .. 'world-aligned support bounds. Does not move the anchor.',
    fogClearing = "How much of the scene's volumetric fog this light burns away where it "
        .. 'shines, like a fog lamp (0..1). Needs Fog > volumetric and lightClearing.',
    gravity = 'Acceleration magnitude in world units per second squared.',
    gravityDirection = 'World-space direction; normalized by the solver. Zero disables gravity.',
    horizontalScrollBarInset = 'Reserve vertical viewport space for the horizontal scrollbar: '
        .. 'None, Always or ScrollBar (only when visible).',
    inheritScale = 'Include spatial parent scale in this node frame and local translation. '
        .. 'False strips parent scale; descendants inherit the resulting frame according to their '
        .. 'own setting. Attachment3D defaults false.',
    interactable = 'Allow mouse/touch input in this branch. False cancels captures without '
        .. 'stopping visual material updates or modifier work.',
    layerGroup = 'Named visibility group chosen from the scene matrix. Legacy internal mask: '
        .. 'camera.layers and shadow masks test shared bits. Not a physics collision group. '
        .. 'Example: 1, 2 or 3 (both).',
    lightEmission = '0 blends normally, 1 adds the colour to the scene (glow). Values between '
        .. 'mix both.',
    linearDamping = 'Linear velocity decay in 1/second (>=0). 0 has no drag; 1 slows free '
        .. 'movement to about 37% in one second. Gravity still applies.',
    maxMeshDistance = 'Maximum camera-to-mesh distance in world units, including bounds radius; '
        .. '0 disables this additional culling. Does not remove shadow casters.',
    occlusionCulling = 'Current-camera conservative opaque triangle coverage. Fully hidden '
        .. 'meshes and strictly covered triangles are skipped in the main pass. Hidden meshes '
        .. 'remain eligible for shadows and other Viewports. CPU cost depends on scene layout.',
    occlusionMaxOccluders = 'Maximum convex coverage polygons tested. Lower budgets reduce '
        .. 'culling opportunities without hiding additional objects.',
    occlusionMinArea = 'Minimum projected candidate AABB area in logical pixels squared.',
    occlusionTriangleBudget = 'Maximum actual occluder triangles inspected for coverage per '
        .. 'rendered frame. No GPU depth readback or previous-frame visibility.',
    offset = 'BillboardUI anchor translation on support-local X/Y/Z axes, in world units. '
        .. 'UIGradient instead uses UDim2: Scale relative to the content area plus pixels.',
    offsetWorldSpace = 'BillboardUI anchor translation on world X/Y/Z axes, in world units.',
    poseMode = 'Collision debug pose. Render: where the visuals are drawn (interpolated between '
        .. 'physics steps). Solver: the newest physics step, which contacts and queries use. Both: '
        .. 'solver shapes in magenta over the normal colours.',
    priority = 'Ranking when nodes compete for one role (the main sun among directional lights, the '
        .. 'detectors answering one click): higher goes first, equal priorities fall back to the '
        .. 'usual order.',
    positionSource = 'Player position source for the Radius check, not the clicked target. None '
        .. 'uses World3D.interactionSource. The target is Parent Mesh3D; distance is measured to '
        .. 'its origin. No camera fallback.',
    radius = 'UICorner: Vector2 Scale/Offset relative to the shorter side, clamped to half that '
        .. 'side. ClickDetector3D: world-unit distance from interaction source to Mesh3D origin.',
    receiveShadow = 'Shadows from other objects darken this node. It only shows when the node '
        .. 'is lit (see its light settings).',
    restitution = 'Bounce coefficient (dimensionless, >=0). Usually 0..1; >1 adds energy. '
        .. 'Example: 0.7 for a bouncing ball. Contact uses both materials.',
    scrollingDirection = 'Allowed scroll axes: X, Y or XY. Changing direction resets the '
        .. 'disabled axis.',
    scrollingEnabled = 'Allow wheel and pointer scrolling and show scrollbars. Programmatic '
        .. 'CanvasPosition remains available.',
    screenSpaceAA = 'Screen-space anti-aliasing applied to the finished image; works with MSAA.',
    sensitivity = 'Degrees per logical pixel for Free cameras. Follow cameras use '
        .. 'followSensitivity.',
    shadowAlphaCutoff = 'Shadow pass only: texels more transparent than this cast no shadow, so '
        .. 'a soft edge does not produce a hard shadow. Unlike Mesh3D alphaCutoff it never changes '
        .. 'how the node is drawn.',
    shadowGroup = 'Layer group that decides which lights this node casts into and receives from.',
    simulationSpace = 'Local (LockedOnPart): existing particles follow the emitter/attachment '
        .. 'position, rotation and scale. World: existing particles stay in world space. Changes '
        .. 'affect new births.',
    supportSize = 'Local bounding dimensions for non-Mesh3D support (including Attachment3D), '
        .. 'default 1 x 1 x 1 world unit before support scale.',
    textureMode = 'Stretch: the image covers the whole ribbon. Wrap: it repeats every '
        .. 'textureLength units and moves with the ribbon. Static: it repeats in world space and '
        .. 'stays put while the ribbon moves. Tiles, Texture, Atlas and XML image modes always use '
        .. 'their own mapping.',
    textureSize = 'Texture repetition size along surface U/V, in world units. Object resize '
        .. 'changes repeat count.',
    textureSpeed = 'Scroll speed of the image along the ribbon in repeats per second.',
    thickness = 'Vector2 Scale/Offset: min(parent width,height)*Scale + pixel Offset. Rendering '
        .. 'clamps Border to 64 px and Text to 8 px.',
    tileSize = 'UDim2 tile size relative to the selected area plus logical pixels. Decal3D '
        .. 'Tiles converts world area using canvasPixelsPerUnit.',
    verticalScrollBarInset = 'Reserve horizontal viewport space for the vertical scrollbar: '
        .. 'None, Always or ScrollBar (only when visible).',
    visible = 'Hide this node and descendants; hidden branches do not receive input or '
        .. 'contribute to automatic scroll length.',
    wireframe = 'Render geometry edges in this World3D. Skips lighting, shadow generation and '
        .. 'occlusion.',
    zOffset = 'World units added to the sorting depth. Positive values draw the ribbon earlier '
        .. '(behind other transparent objects).',
}

-- Texts several category files repeat for different classes.
local shared = {
    lightInfluence = '0: unlit, the node shows its own colour and ignores lights, shadows, fog '
        .. 'and tone mapping. 1: fully lit by the scene. Values in between blend the two.',
    optionalImage = 'Optional image override. An empty path uses the XML manifest image in XML '
        .. 'mode.',
    renderRange = 'Render cutoff distance from the camera in world units; 0 disables it.',
    ribbonTexture = 'Image path, for example scene://assets/textures/trail.png. Empty or '
        .. 'missing files render the diagnostic checker. Use pixelate for nearest filtering.',
    surfaceBrightness = 'Colour multiplier applied after lighting. 1 keeps the colour, 0 is '
        .. 'black, values above 1 brighten.',
}

return { keys = keys, shared = shared }

local propertyAliases = {
    fieldOfView = 'fov',
    FieldOfView = 'fov',
    camera2D = 'currentCamera',
    Camera2D = 'currentCamera',
    MaxBoneInfluences = 'maxBoneInfluences',
    BonePaletteLimit = 'bonePaletteLimit',
    ZIndex = 'zIndex',
    Order = 'order',
    GeometrySource = 'geometrySource',
    CollisionLevel = 'collisionLevel',
    Attachment0 = 'attachment0',
    Attachment1 = 'attachment1',
    FadeIn = 'fadeIn',
    FadeOut = 'fadeOut',
    Speed = 'speed',
    CastShadow = 'castShadow',
    ReceiveShadow = 'receiveShadow',
    ShadowGroup = 'shadowGroup',
    ScrollingDirection = 'scrollingDirection',
    ScrollingEnabled = 'scrollingEnabled',
    CanvasPosition = 'canvasPosition',
    AutomaticCanvasSize = 'automaticCanvasSize',
    AbsoluteCanvasSize = 'absoluteCanvasSize',
    AbsoluteWindowSize = 'absoluteWindowSize',
    HorizontalScrollBarInset = 'horizontalScrollBarInset',
    VerticalScrollBarInset = 'verticalScrollBarInset',
    ScrollBarThickness = 'scrollBarThickness',
    ScrollBarImageColor3 = 'scrollBarImageColor3',
    ScrollBarImageTransparency = 'scrollBarImageTransparency',
    TopImage = 'topImage',
    MidImage = 'midImage',
    BottomImage = 'bottomImage',
    VerticalScrollBarPosition = 'verticalScrollBarPosition',
    Transparency = 'transparency',
    ColorMap = 'colorMap',
    NormalMap = 'normalMap',
    RoughnessMap = 'roughnessMap',
    MetalnessMap = 'metalnessMap',
    EmissionMap = 'emissionMap',
    EmissionStrength = 'emissionStrength',
    Playing = 'playing',
    Enabled = 'enabled',
    LayerGroup = 'layerGroup',
    Gravity = 'gravity',
    GravityDirection = 'gravityDirection',
    TimeScale = 'timeScale',
    Pixelate = 'pixelate',
    CanvasSize = 'canvasSize',
    ShaderTransparency = 'shaderTransparency',
    BackgroundTransparency = 'backgroundTransparency',
    ShaderPath = 'shaderPath',
    ImageMode = 'imageMode',
    PlaybackTime = 'playbackTime',
}

local function inheritInitializers(class, instance)
    if class.base then
        inheritInitializers(class.base, instance)
    end
    if rawget(class, 'initialize') then
        class.initialize(instance)
    end
    require('source.engine.nodes.core.extensions').run(class.name, instance)
end
-- Properties a class never reads (spatial ones, or `visible` on nodes that draw nothing and own no
-- children). They do not exist on its nodes: no default value, no
-- inspector row, no clone entry. A plugin class lists its own in `omit = { 'scale', ... }`.
local omit = {
    NavMap3D = {
        'rotation', 'scale', 'inheritScale', 'transparency', 'layerGroup', 'shadowGroup', 'visible',
    },
    NavLink3D = {
        'rotation', 'scale', 'inheritScale', 'transparency', 'layerGroup', 'shadowGroup', 'visible',
    },
    NavArea3D = { 'transparency', 'layerGroup', 'shadowGroup', 'visible' },
    NavObstacle3D = { 'transparency', 'layerGroup', 'shadowGroup', 'visible' },
    Attachment3D = { 'transparency', 'layerGroup', 'shadowGroup' },
    PointLight3D = { 'transparency', 'scale', 'inheritScale', 'rotation' },
    SpotLight3D = { 'transparency', 'scale', 'inheritScale' },
    DirectionalLight3D = { 'transparency', 'scale', 'inheritScale', 'position' },
    Camera3D = { 'transparency', 'scale' },
    Beam3D = { 'position', 'rotation', 'scale', 'inheritScale' },
    Trail3D = { 'position', 'rotation', 'scale', 'inheritScale' },
    NavAgent3D = { 'visible' },
    UIStyler = { 'visible' },
    Camera2D = { 'transparency', 'visible' },
    Attachment2D = { 'transparency' },
    InverseKinematics3D = { 'visible' },
}

local cache = setmetatable({}, { __mode = 'k' })

-- The set of omitted property names of a class (own list, plugin list and ancestors').
local function omitted(class)
    local set = class and cache[class]
    if set then
        return set
    end
    set = {}
    local node = class
    while node do
        for _, list in ipairs({ omit[node.name] or {}, rawget(node, 'omit') or {} }) do
            for _, key in ipairs(list) do
                set[key] = true
            end
        end
        node = node.base
    end
    if class then
        cache[class] = set
    end
    return set
end

return { propertyAliases = propertyAliases, initialize = inheritInitializers, omitted = omitted }

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
return { propertyAliases = propertyAliases, initialize = inheritInitializers }

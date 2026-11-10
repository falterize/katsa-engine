-- Inspector descriptions of screen UI nodes.
-- Editor text only: the classes carry no hint of their own.
-- Shape: { ClassName = { property = 'text' } }; a subclass inherits its base class entries.
local Common = require('./common')

return {
    Button = {
        image = Common.shared.optionalImage,
    },
    ImageRect = {
        image = Common.shared.optionalImage,
    },
    Label = {
        textKey = 'Localization key. When set, the text follows the current language '
            .. '(Localization.get():setLocale) and `text` is filled from the key.',
    },
    ScrollFrame = {
        bounceSpeed = 'How quickly the stretch springs back after release (per second).',
        canvasSize = 'UDim2 canvas dimensions relative to the frame plus logical pixels. '
            .. 'AutomaticCanvasSize can extend the authored minimum.',
        dragWithMouse = 'Swipe-scroll with the mouse (hold and drag the content). Touch always '
            .. 'swipes; the mouse only does when this is on. The scrollbar thumb and wheel work '
            .. 'either way.',
        inertia = 'How far the content keeps gliding after a swipe. 0 stops dead, 1 glides for '
            .. 'a long time.',
        overscroll = 'Rubber-band stretch past the ends as a fraction of the window size. 0 '
            .. 'hard stops, 0.25 feels like a phone list.',
    },
    TileMap = {
        cellSize = 'Size of one cell on screen, in UI pixels.',
        mapFile = 'Lua file with saved cells (TileMap:toData). Loaded when it changes.',
        pixelate = 'Sharp pixels instead of smoothing; right for pixel art.',
        tileSet = 'Lua file that returns the tileset: image, tile grid, solid tiles and terrains.',
    },
}

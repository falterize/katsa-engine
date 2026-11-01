local Flipbook = require('source.engine.animation.flipbook')
local FlipbookXml = {}
local entities = { amp = '&', lt = '<', gt = '>', quot = '"', apos = "'" }
local rootKeys = {
    version = true,
    image = true,
    columns = true,
    rows = true,
    frameWidth = true,
    frameHeight = true,
    pixelate = true,
    initial = true,
}
local animationKeys = { name = true, fps = true, loop = true }
local frameKeys = { index = true }

local function attributes(text, allowed)
    local values, position = {}, 1
    while text:sub(position):find('%S') do
        local key, quote, value, finish = text:sub(position)
            :match([[^%s*([%a_][%w_:%-]*)%s*=%s*(['"])(.-)%2()]])
        assert(key and allowed[key], 'Flipbook XML: unknown or malformed attribute')
        assert(values[key] == nil, 'Flipbook XML: duplicate attribute ' .. key)
        value = value:gsub('&([^;]+);', function(entity)
            return assert(entities[entity], 'Flipbook XML: unsupported entity ' .. entity)
        end)
        values[key], position = value, position + finish - 1
    end
    return values
end

local function integer(value, name, minimum)
    local number = tonumber(value)
    assert(
        number and number >= minimum and number < math.huge and number % 1 == 0,
        'Flipbook XML: invalid ' .. name
    )
    return number
end

local function boolean(value, default)
    if value == nil then
        return default
    end
    assert(value == 'true' or value == 'false', 'Flipbook XML: expected true or false')
    return value == 'true'
end

-- A strict animation-manifest reader, not a general XML document evaluator.
-- The narrow schema rejects unknown tags/attributes instead of ignoring typos.
function FlipbookXml.parse(text)
    assert(type(text) == 'string', 'Flipbook XML requires text')
    text = text:gsub('^\239\187\191', ''):gsub('<!%-%-.-%-%->', ''):gsub('^%s*<%?xml.-%?>', '')
    assert(
        not text:find('<!', 1, true) and not text:find('<?', 1, true),
        'Flipbook XML: declarations other than the XML header are unsupported'
    )
    local header, body = text:match('^%s*<flipbook(%s.-)>(.*)</flipbook>%s*$')
    assert(header, 'Flipbook XML: expected a flipbook root element')
    local settings = attributes(header, rootKeys)
    assert(settings.version == '1', 'Flipbook XML: expected version="1"')
    assert(settings.image and settings.image:match('%S'), 'Flipbook XML: missing image path')
    local columns, rows = integer(settings.columns, 'columns', 1), integer(settings.rows, 'rows', 1)
    local definition = {
        image = settings.image,
        columns = columns,
        rows = rows,
        pixelate = boolean(settings.pixelate, false),
        clips = {},
    }
    if settings.frameWidth or settings.frameHeight then
        definition.frameWidth = integer(settings.frameWidth, 'frameWidth', 1)
        definition.frameHeight = integer(settings.frameHeight, 'frameHeight', 1)
    end
    local position, first = 1, nil
    while body:sub(position):find('%S') do
        local start, finish, clipText, frameText =
            body:find('%s*<animation(%s.-)>(.-)</animation>', position)
        assert(start == position, 'Flipbook XML: expected an animation element')
        local clip = attributes(clipText, animationKeys)
        assert(
            clip.name and clip.name:match('^[%a_][%w_%-]*$'),
            'Flipbook XML: invalid animation name'
        )
        assert(not definition.clips[clip.name], 'Flipbook XML: duplicate animation ' .. clip.name)
        local fps = tonumber(clip.fps)
        assert(fps and fps > 0 and fps < math.huge, 'Flipbook XML: fps must be finite and positive')
        local frames, cursor = {}, 1
        while frameText:sub(cursor):find('%S') do
            local a, b, frame = frameText:find('%s*<frame(%s.-)/>', cursor)
            assert(a == cursor, 'Flipbook XML: expected a self-closing frame element')
            local index = integer(attributes(frame, frameKeys).index, 'frame index', 0)
            assert(index < columns * rows, 'Flipbook XML: frame index exceeds atlas dimensions')
            frames[#frames + 1], cursor = index, b + 1
        end
        assert(#frames > 0, 'Flipbook XML: animation must contain frames')
        definition.clips[clip.name] =
            { fps = fps, frames = frames, loop = boolean(clip.loop, true) }
        first, position = first or clip.name, finish + 1
    end
    definition.initial = settings.initial or first
    assert(
        definition.initial and definition.clips[definition.initial],
        'Flipbook XML: initial animation is missing'
    )
    return definition
end

function FlipbookXml.read(resources, path)
    local canonical = resources:canonical(path)
    local text = assert(katsa.filesystem.read(canonical), 'Missing flipbook XML: ' .. tostring(path))
    local ok, definition = pcall(FlipbookXml.parse, text)
    assert(ok, 'Invalid flipbook XML ' .. tostring(path) .. ': ' .. tostring(definition))
    return definition
end

function FlipbookXml.bind(resources, target, source)
    local path = target.xml
    assert(type(path) == 'string' and path ~= '', 'XML image mode requires an xml path')
    local binding = target._xmlBinding
    local changed = not binding or binding.resources ~= resources or binding.path ~= path
    local definition = changed and FlipbookXml.read(resources, path) or binding.definition
    local field = target.colorMap ~= nil and 'colorMap'
        or target.texture ~= nil and 'texture'
        or 'image'
    source = source or target[field]
    local automatic = source == nil
        or source == ''
        or binding and binding.automatic and source == binding.source
    if automatic then
        source = definition.image
    end
    if changed or binding.source ~= source then
        local selected = source
        if definition.frameWidth then
            local image = type(source) == 'string' and resources:image(source) or source
            if
                not (type(source) == 'string' and resources:isMissingImage(source))
                and (
                    image:getWidth() ~= definition.columns * definition.frameWidth
                    or image:getHeight() ~= definition.rows * definition.frameHeight
                )
            then
                selected = 'assets/textures/internal/missing.png'
                if resources.store.journal then
                    resources.store.journal:record(
                        'Resources',
                        'XML atlas size mismatch: '
                            .. tostring(source)
                            .. '; expected '
                            .. definition.columns * definition.frameWidth
                            .. 'x'
                            .. definition.rows * definition.frameHeight,
                        target,
                        path
                    )
                end
            end
        end
        -- Validate before committing. Image overrides do not reparse metadata or
        -- restart playback, and rendering never resets a manually selected frame.
        if changed then
            target.atlasGrid = { definition.columns, definition.rows }
            target.pixelate = definition.pixelate
        end
        target._xmlBinding = {
            resources = resources,
            path = path,
            definition = definition,
            image = selected,
            source = source,
            automatic = automatic,
        }
    end
    target._xmlBinding.automatic = automatic
    if automatic and target[field] ~= source then
        target[field] = source
    end
    return definition
end

function FlipbookXml.playback(resources, target)
    local definition = FlipbookXml.bind(resources, target)
    local playback = Flipbook.new(target, definition.clips)
    playback.source = target.xml
    playback:play(definition.initial)
    return playback
end

function FlipbookXml.load(resources, path, target)
    target.xml, target.imageMode = path, 'XML'
    return FlipbookXml.playback(resources, target)
end

return FlipbookXml

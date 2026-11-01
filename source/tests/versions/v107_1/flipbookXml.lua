local Xml = require('source.engine.animation.formats.flipbookXml')
local Tests = {}

function Tests.run(tester)
    local path = 'source/game/scenes/abilityRunner2D/assets/animations/player.xml'
    local text = assert(katsa.filesystem.read(path))
    local definition = Xml.parse(text)
    tester:check(
        definition.frameWidth == 8
            and definition.frameHeight == 8
            and definition.columns == 8
            and definition.rows == 1
            and definition.pixelate,
        'XML declares the complete eight-frame 8x8 atlas configuration'
    )
    tester:check(
        definition.initial == 'Idle'
            and definition.clips.Run.fps == 10
            and #definition.clips.Run.frames == 4
            and definition.clips.Run.frames[4] == 3,
        'XML preserves named states, playback rates and repeated frame order'
    )
    tester:check(
        definition.clips.Idle.loop and not definition.clips.Jump.loop,
        'XML declares looping and held final-frame clips independently'
    )
    local single = Xml.parse(text:gsub('"', "'"))
    tester:check(
        single.image == definition.image,
        'Animation XML accepts single and double quoted attributes'
    )
    local escaped = Xml.parse(text:gsub('player.png', 'player&amp;extra.png'))
    tester:check(
        escaped.image == 'scene://textures/player&extra.png',
        'Animation XML decodes escaped attribute values'
    )
    local invalid = {
        { text:gsub('fps="10"', 'fps="0"'), 'zero playback rate' },
        { text:gsub('index="7"', 'index="8"'), 'out-of-range atlas index' },
        { text:gsub('name="Run"', 'name="Idle"'), 'duplicate state' },
        { text:gsub('fps="10"', 'speed="10"'), 'misspelled attribute' },
        { text:gsub('<frame index="0" />', '<command index="0" />'), 'unknown child tag' },
        { text:gsub('initial="Idle"', 'initial="Missing"'), 'missing initial state' },
        { text:gsub('</animation>', '</wrong>'), 'mismatched closing element' },
        { '<!DOCTYPE flipbook SYSTEM "external.xml">' .. text, 'document declaration' },
    }
    for _, case in ipairs(invalid) do
        tester:check(not pcall(Xml.parse, case[1]), 'Animation XML rejects ' .. case[2])
    end
end

return Tests

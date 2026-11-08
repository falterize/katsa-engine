-- Scene tags: parsing, filtering and the menu list.
local Module = {}

function Module.run(self)
    local Tags = require('source.game.sceneTags')
    self:check(
        table.concat(Tags.of({ tags = { 'Physics', '2D', 'physics' } }), ',') == 'physics,2d',
        'Tags are lowercase and unique'
    )
    self:check(Tags.of({ category = 'Games' })[1] == 'games', 'A scene without tags falls back to its category')
    local entries = {
        { title = 'Physics 2D', id = 'physics2D', tags = { 'physics', '2d' } },
        { title = 'Cars', id = 'multiplayerCars', tags = { 'game', 'physics', '3d' } },
        { title = 'Audio', id = 'audioNodes', tags = { 'audio' } },
    }
    local function ids(selected, query)
        local found = {}
        for _, entry in ipairs(entries) do
            if Tags.matches(entry, selected, Tags.words(query)) then
                found[#found + 1] = entry.id
            end
        end
        return table.concat(found, ',')
    end
    self:check(ids({}, '') == 'physics2D,multiplayerCars,audioNodes', 'No filter lists every scene')
    self:check(ids({ physics = true }, '') == 'physics2D,multiplayerCars', 'A tag keeps the scenes that have it')
    self:check(ids({ physics = true, ['3d'] = true }, '') == 'multiplayerCars', 'Several tags must all match')
    self:check(ids({}, 'CARS') == 'multiplayerCars', 'Search words match titles, ignoring case')
    self:check(ids({}, 'game 3d') == 'multiplayerCars', 'Search words also match tags')
    local collected = Tags.collect(entries)
    self:check(collected[1].tag == 'physics' and collected[1].count == 2, 'Tags are listed most used first')

    -- Every shipped scene lists tags, and the menu shows them.
    local Catalog = require('source.game.sceneCatalog')
    local Loader = require('source.engine.scenes.loader')
    local missing = {}
    for _, entry in ipairs(Catalog.entries) do
        local package = Loader.open(entry.id, Catalog)
        if not package.settings.tags or #package.settings.tags == 0 then
            missing[#missing + 1] = entry.id
        end
        package:release()
    end
    self:check(#missing == 0, 'Every catalog scene lists tags' .. (#missing > 0 and (': ' .. table.concat(missing, ',')) or ''))
end

return Module

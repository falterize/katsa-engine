-- Reads a `conf.lua`. One format for every kind of source (game, project, scene): the file returns
-- a table of settings (see docs/book/conf.md).
local Conf = {}

-- Runs the file through filesystem `FS` and returns its table.
function Conf.read(FS, path)
    local chunk = assert(FS.load(path))
    local result = chunk()
    assert(type(result) == 'table', path .. ' must return a table')
    return result
end

-- Applies `values` over `target` (nested tables are merged, everything else replaced).
function Conf.merge(target, values)
    for key, value in pairs(values or {}) do
        if type(value) == 'table' and type(target[key]) == 'table' then
            Conf.merge(target[key], value)
        else
            target[key] = value
        end
    end
    return target
end

return Conf

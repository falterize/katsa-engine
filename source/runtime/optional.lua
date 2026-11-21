-- require() for a module that may legitimately not exist (the examples' project and catalog):
-- returns nil only when the module is missing; a syntax or runtime error in it still raises.
local Optional = {}

function Optional.require(name)
    local ok, result = pcall(require, name)
    if ok then
        return result
    end
    if type(result) == 'string' and result:find("module '" .. name .. "' not found", 1, true) then
        return nil
    end
    error(result, 0)
end

return Optional

-- A graph value is a number, the name of a tree parameter, or a function of the parameters.
local Params = {}

function Params.read(tree, reference, fallback)
    local kind = type(reference)
    if kind == 'number' then
        return reference
    elseif kind == 'string' then
        local value = tree.params[reference]
        if type(value) == 'boolean' then
            return value and 1 or 0
        end
        return value or fallback or 0
    elseif kind == 'function' then
        return reference(tree.params, tree)
    end
    return fallback or 0
end

return Params

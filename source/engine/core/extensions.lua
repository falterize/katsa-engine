local Extensions = {}

-- Assemble class responsibilities once at module load. Modules retain their
-- own helpers and dependencies; instances only receive the exported methods.
function Extensions.apply(class, methods)
    for name, method in pairs(methods) do
        if type(method) == 'function' then
            class[name] = method
        end
    end
end

return Extensions

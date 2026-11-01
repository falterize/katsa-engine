local Runtime = { worlds = {} }
local token = 0

function Runtime.nextToken()
    token = token + 1
    return token
end

return Runtime

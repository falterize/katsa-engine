-- The device benchmark game (tools/diagnostics/androidBench) loads and defines its callbacks.
local Module = {}

function Module.run(self)
    local chunk, message = loadfile('tools/diagnostics/androidBench/main.lua')
    self:check(chunk ~= nil, 'The bench main.lua compiles: ' .. tostring(message))
    local conf = loadfile('tools/diagnostics/androidBench/conf.lua')
    self:check(conf and conf().identity == 'katsa-bench', 'The bench has its own save identity')
end

return Module

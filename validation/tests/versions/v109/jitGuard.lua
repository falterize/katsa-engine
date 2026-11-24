-- A storm of trace-cache flushes turns the JIT off; a few flushes do not.
local Module = {}

function Module.run(self)
    local Guard = require('source.engine.core.jitGuard')
    Guard.install()
    Guard.limit, Guard.window = 5, 1
    jit.flush()
    Guard.update(100)
    Guard.update(101.5)
    self:check(not Guard.disabled and jit.status(), 'A single flush leaves the JIT on')
    for _ = 1, 8 do
        jit.flush()
    end
    Guard.update(103)
    local off = Guard.disabled and not jit.status()
    jit.on()
    Guard.disabled, Guard.limit, Guard.window = false, 30, 2
    self:check(off, 'Many flushes within a window turn the JIT off')
end

return Module

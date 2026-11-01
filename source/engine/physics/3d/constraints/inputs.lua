-- Reuses scalar slots. Preserve the old %.5f endpoint precision without building
-- concatenated keys every fixed step; unchanged raw inputs need no formatting.
local Inputs = {}
Inputs.__index = Inputs

function Inputs.begin(owner, a, b, kind)
    local state = owner._constraintInputs
    if not state then
        state = setmetatable({ raw = {}, values = {}, revision = 0 }, Inputs)
        owner._constraintInputs = state
    end
    state.index = 0
    state.changed = false
    state:value(a)
    state:value(b)
    state:value(kind)
    state:value(a.colliderRevision)
    state:value(b.colliderRevision)
    return state
end

function Inputs:value(value)
    local i = self.index + 1
    self.index = i
    if self.values[i] ~= value then
        self.values[i] = value
        self.changed = true
    end
    self.raw[i] = value
end

function Inputs:number(value)
    local i = self.index + 1
    self.index = i
    if self.raw[i] ~= value or self.values[i] == nil then
        local token = string.format('%.5f', value)
        if token == '-0.00000' then
            token = '0.00000'
        end
        self.raw[i] = value
        if self.values[i] ~= token then
            self.values[i] = token
            self.changed = true
        end
    end
end

function Inputs:vector(value)
    for i = 1, #value do
        self:number(value[i])
    end
end

function Inputs:finish()
    if self.count ~= self.index then
        self.changed = true
    end
    for i = self.count or 0, self.index + 1, -1 do
        self.raw[i], self.values[i] = nil, nil
    end
    self.count = self.index
    if self.changed then
        self.revision = self.revision + 1
    end
    return self.revision
end

return Inputs

-- Error-only bounded storage: there is no frame polling or tree traversal.
local Journal = {}
Journal.__index = Journal

function Journal.new(limit)
    return setmetatable({ entries = {}, limit = limit or 64 }, Journal)
end

function Journal:record(system, message, node, script)
    local entry = {
        system = system,
        message = tostring(message),
        node = node and (node.name or node.className) or '',
        class = node and node.className or '',
        script = script or '',
        time = katsa.timer.getTime(),
    }
    self.entries[#self.entries + 1] = entry
    katsa.log.error(entry.message, system, true)
    if #self.entries > self.limit then
        table.remove(self.entries, 1)
    end
    return entry
end

-- Warnings go to the console and log only; they are not runtime errors, so they stay out of
-- `entries` (which tests and the diagnostics panel treat as failures).
function Journal:warn(system, message, node)
    local owner = node and (node.name or node.className)
    local text = owner and (tostring(owner) .. ': ' .. tostring(message)) or tostring(message)
    katsa.log.warn(text, system, false)
    return text
end

function Journal:clear()
    self.entries = {}
end

return Journal

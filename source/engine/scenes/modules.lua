-- Scene modules: optional features that a runtime installs from a list of module paths. The
-- engine knows nothing about the modules themselves; a runtime that is given no list behaves as
-- before, so removing a module is deleting its folder and its list entry.
--
-- A module is `require(path).install(scene)` returning a table with an optional `name` and any of
-- the hooks the runtime emits (`created`, `resize`, `update`, `keypressed`, ...). Hooks run in
-- list order; `consume` stops at the first hook that returns true.
local Array = require('../math.array')

local ipairs, pairs = Array.ipairs, Array.pairs

local Modules = { methods = {} }
local Methods = Modules.methods
local EMPTY = {}

function Modules.install(scene, paths)
    scene.moduleList, scene.moduleMap = {}, {}
    for _, path in ipairs(paths or EMPTY) do
        local module = require(path).install(scene)
        if module then
            scene.moduleList[#scene.moduleList + 1] = module
            scene.moduleMap[module.name or path] = module
        end
    end
end

-- The installed module with this name, or nil when it is not installed.
function Methods:module(name)
    return self.moduleMap and self.moduleMap[name]
end

-- Calls the hook on every module.
function Methods:emit(hook, ...)
    for _, module in ipairs(self.moduleList or EMPTY) do
        local run = module[hook]
        if run then
            run(module, ...)
        end
    end
end

-- Calls the hook until one module returns true; true when a module took the event.
function Methods:consume(hook, ...)
    for _, module in ipairs(self.moduleList or EMPTY) do
        local run = module[hook]
        if run and run(module, ...) then
            return true
        end
    end
    return false
end

-- Copies the module methods onto a runtime class.
function Modules.extend(class)
    for name, method in pairs(Methods) do
        class[name] = method
    end
end

return Modules

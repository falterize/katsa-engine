-- What every light node class shares: the shadow options, the creation defaults and the mount
-- that registers the node as a light of its World3D (the render loop reads `world.lights`).
-- A class installs it with `Light.install(Class)`; DirectionalLight3D, PointLight3D and
-- SpotLight3D differ only in the properties they own (see `omit` in classPolicy).
local Shadowing = require('./shadowing')

local Light = {}

function Light.initialize(self)
    Shadowing.normalize(self, { castShadow = true })
end

-- Creates the light through the world. `properties.className` is the light type.
function Light.mount(world, properties, parent)
    properties.parent = parent
    properties.type = properties.className
    return world:addLight(properties)
end

function Light.install(Class)
    Shadowing.describe(Class, { receive = false, cutoff = false })
    Class.initialize = Light.initialize
    Class.mount = Light.mount
end

return Light

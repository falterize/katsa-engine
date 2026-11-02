-- Quality profiles change numeric settings only and never raise an authored shadow resolution.
local World = require('source.engine.world.world')
local Profiles = require('source.engine.graphics.quality.profiles')

local Module = {}

function Module.run(self)
    local world = World.new(self.manager.resources:scope())
    local environment = world.environment
    environment.shadows.resolution = 1024
    environment.shadows.enabled = true
    environment:applyQualityProfile('Low')
    self:check(
        environment.render.renderDensity == 0.75 and environment.render.msaa == 0,
        'Low profile lowers render density and MSAA'
    )
    self:check(
        environment.shadows.resolution == 512 and environment.shadows.updateHz == 20,
        'Low profile caps shadow resolution and update rate'
    )
    self:check(environment.shadows.enabled == true, 'profiles keep shadows enabled')
    environment.shadows.resolution = 256
    environment:applyQualityProfile('High')
    self:check(
        environment.shadows.resolution == 256 and environment.shadows.updateHz == 60,
        'High profile never raises an authored shadow resolution'
    )
    self:check(
        Profiles.next('Low') == 'Medium' and Profiles.next('High') == 'Low',
        'profile cycling wraps around'
    )
    self:check(
        not pcall(environment.applyQualityProfile, environment, 'Nope'),
        'unknown profiles are rejected'
    )
end

return Module

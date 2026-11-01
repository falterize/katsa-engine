-- Vehicle plugin entry: Vehicle.new(config, ground), Vehicle.Collision, Vehicle.Deformation.
local Vehicle = require('source.plugins.vehicle.model')
Vehicle.Collision = require('source.plugins.vehicle.collision')
Vehicle.Deformation = require('source.plugins.vehicle.deformation')
return Vehicle

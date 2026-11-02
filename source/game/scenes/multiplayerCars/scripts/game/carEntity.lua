-- Replicated definition of a car, shared by the server and every client so prediction and
-- authority use one step function. The simulated object is the vehicle model itself.
local Model = require('scene.nodes.vehicle.model')
local Deformation = require('scene.nodes.vehicle.deformation')
local Arena = require('scene.scripts.game.arena')

local CarEntity = {}

-- Where a flipped car is put back (shared by the server and driving clients).
function CarEntity.spawnPoint(netId)
    return Arena.spawns[(netId - 1) % #Arena.spawns + 1]
end

local MAX_IMPACTS = 8

-- Builds a car from spawn args { x, z, heading, seats = { id or 0, x4 }, dents = {..}, nitro, bot, color }.
function CarEntity.create(_, args)
    local car = Model.new(args.config, Arena.ground)
    car:setPose(args.x or 0, args.z or 0, args.heading or 0)
    car.nitro = args.nitro or 1
    car.pitch, car.roll = 0, 0
    car.impacts = {}
    car.dents = Deformation.new()
    car.dents:load(args.dents)
    car.isBot = args.bot == true
    car.color = args.color
    for index, id in ipairs(args.seats or {}) do
        if id ~= 0 then
            car.seats[index] = id
        end
    end
    return car
end

local function springField(name)
    return tonumber(name:match('^spring(%d)$'))
end

local function get(car, name)
    if name == 'position' then
        return { car.x, car.y, car.z }
    end
    local index = springField(name)
    if index then
        return car.spring[index]
    end
    return car[name]
end

local function set(car, name, value)
    if name == 'position' then
        car.x, car.y, car.z = value[1], value[2], value[3]
        return
    end
    local index = springField(name)
    if index then
        car.spring[index] = value
        return
    end
    car[name] = value
end

CarEntity.definition = {
    create = CarEntity.create,
    get = get,
    set = set,
    despawnWithAuthority = false, -- a car outlives its driver
    -- The driver's client owns the car's physics while someone is at the wheel; the server
    -- takes it back (authority nil) when the seat is empty.
    clientAuthoritative = true,
    fields = {
        'position:vec3',
        'heading:angle',
        'speed:f32',
        'slide:f32',
        'nitro:f32',
        'steerAngle:f32',
        'pitch:angle',
        'roll:angle',
        'spring1:f32',
        'spring2:f32',
        'spring3:f32',
        'spring4:f32',
    },
}

-- Defines the car kind on a Net.Server or Net.Client. The server keeps each driver's input only
-- for cars it simulates itself; clients interpolate cars they do not own.
function CarEntity.define(target)
    local copy = {}
    for key, value in pairs(CarEntity.definition) do
        copy[key] = value
    end
    target:define('Car', copy)
end

return CarEntity

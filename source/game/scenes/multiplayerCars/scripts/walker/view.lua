-- The visible side of a walker: the StareShooter character, animated from the replicated pose,
-- blends and jump counter (the same weighting as the source scene's animation controller).
local Models = require('source.engine.import.models')
local Math = require('./math')
local WalkerEntity = require('../game.walkerEntity')

local WalkerView = {}
WalkerView.__index = WalkerView

local TRACKS = { 'Idle', 'Walk', 'Crouch', 'Fall', 'Jump' }

function WalkerView.new(scene, netId, model)
    local world = scene.world
    local self = setmetatable({
        model = model,
        netId = netId,
        airBlend = 0,
        jumpSequence = model.jumpSequence or 0,
        jumpTime = 1,
        tracks = {},
    }, WalkerView)
    self.root = world:create('Node3D', { name = 'Walker' .. netId })
    local asset = Models.load('scene://models/character.glb', scene.resources)
    Models.instantiate(world, asset, {
        name = 'WalkerModel' .. netId,
        rotation = { 0, 180, 0 }, -- the glTF character faces -z
        scale = { 0.65, 0.65, 0.65 },
        parent = self.root,
    })
    self.asset = asset
    if asset.animator then
        for _, name in ipairs(TRACKS) do
            local track = asset.animator:load('Player_' .. name, { looped = name ~= 'Jump' })
            track:play(0, name == 'Jump' and 2 or 1, name == 'Idle' and 1 or 0)
            self.tracks[name] = track
        end
    end
    return self
end

function WalkerView:update(dt)
    local model, tracks = self.model, self.tracks
    local state = WalkerEntity.states[model.state or 1]
    local riding = state == 'drive' or state == 'passenger'
    self.root.visible = not riding
    self.root.position = { model.rx or model.x, model.ry or model.y, model.rz or model.z }
    -- Engine yaw runs opposite to the model heading.
    self.root.rotation = { 0, -(model.rheading or model.heading or 0), 0 }
    if riding or not tracks.Idle then
        return
    end
    self.airBlend = Math.approach(self.airBlend, model.air and 1 or 0, dt / 0.25)
    if self.jumpSequence ~= model.jumpSequence then
        self.jumpSequence, self.jumpTime = model.jumpSequence, 0
        tracks.Jump:play(0, 2, 0)
    end
    self.jumpTime = self.jumpTime + dt
    local duration = tracks.Jump.clip.duration / 2
    local jumpWeight =
        math.min(1, math.max(0, self.jumpTime / 0.1), math.max(0, (duration - self.jumpTime) / 0.1))
    local ground = 1 - self.airBlend
    local walk, crouch =
        model.rwalk or model.walkBlend or 0, model.rcrouch or model.crouchBlend or 0
    tracks.Idle.weight = ground * (1 - crouch) * (1 - walk)
    tracks.Walk.weight = ground * (1 - crouch) * walk
    tracks.Crouch.weight = ground * crouch
    tracks.Fall.weight = self.airBlend * (1 - jumpWeight)
    tracks.Jump.weight = self.airBlend * jumpWeight
    tracks.Walk.speed, tracks.Crouch.speed = model.walkScale or 0, model.walkScale or 0
end

function WalkerView:destroy()
    self.root:destroy()
end

return WalkerView

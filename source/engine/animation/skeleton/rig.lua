local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local M = require('../../math.math3d')
local Pose = require('./pose')

local Rig = {}

local function sameCopy(source, snapshot, count)
    local changed = false
    for i = 1, count do
        if snapshot[i] ~= source[i] then
            snapshot[i] = source[i]
            changed = true
        end
    end
    return changed
end

local function visit(model, index)
    local n = model.nodes[index + 1]
    local cache = n._poseInputs
    if not cache then
        cache =
            { t = {}, r = {}, s = {}, matrix = {}, parent = {}, localOutput = {}, worldOutput = {} }
        n._poseInputs = cache
    end
    local localChanged = cache.matrixMode ~= (n.matrix ~= nil)
    cache.matrixMode = n.matrix ~= nil
    if n.matrix then
        localChanged = sameCopy(n.matrix, cache.matrix, 16) or localChanged
    else
        localChanged = sameCopy(n.translation, cache.t, 3) or localChanged
        localChanged = sameCopy(n.rotation, cache.r, 4) or localChanged
        localChanged = sameCopy(n.scale, cache.s, 3) or localChanged
    end
    -- Matrices are public mutable arrays. Compare outputs too, so an external
    -- in-place edit is repaired even when the authored TRS inputs are unchanged.
    localChanged = sameCopy(n.localPose, cache.localOutput, 16) or localChanged
    if localChanged then
        if n.matrix then
            for i = 1, 16 do
                n.localPose[i] = n.matrix[i]
            end
        else
            M.trs(n.translation, n.rotation, n.scale, n.localPose)
        end
        sameCopy(n.localPose, cache.localOutput, 16)
        model.poseLocalUpdates = (model.poseLocalUpdates or 0) + 1
    end
    local worldChanged = cache.parentNode ~= n.parent
    cache.parentNode = n.parent
    if n.parent then
        worldChanged = sameCopy(n.parent.world, cache.parent, 16) or worldChanged
    end
    worldChanged = sameCopy(n.world, cache.worldOutput, 16) or worldChanged
    if localChanged or worldChanged then
        if n.parent then
            M.multiply(n.parent.world, n.localPose, n.world)
        else
            for i = 1, 16 do
                n.world[i] = n.localPose[i]
            end
        end
        sameCopy(n.world, cache.worldOutput, 16)
        model.poseWorldUpdates = (model.poseWorldUpdates or 0) + 1
    end
    if n.instance and not n.physicalInstance and n.instance.poseMatrix ~= n.localPose then
        n.instance.poseMatrix = n.localPose
    end
    for _, child in ipairs(n.children) do
        visit(model, child)
    end
end

function Rig.initialize(model)
    model.byNodeName = {}
    for i, n in ipairs(model.nodes) do
        n.index = i
        n.rest = {
            translation = Pose.copy(n.translation),
            rotation = Pose.copy(n.rotation),
            scale = Pose.copy(n.scale),
        }
        n.localPose = n.matrix and { unpack(n.matrix) } or M.trs(n.translation, n.rotation, n.scale)
        model.byNodeName[n.name] = n
    end
    for _, clip in ipairs(model.animations) do
        clip.markers = clip.markers or {}
    end

    function model:play(index)
        local controller = self.animator or self.controller
        assert(controller, 'Instantiate an animated model before playing animations')
        if self.legacyTrack then
            self.legacyTrack:stop()
        end
        self.legacyTrack = controller:load(index)
        self.legacyTrack.looped = self.loop ~= false
        self.legacyTrack:play()
    end

    function model:update(dt)
        -- Animator owns advancement; legacy scene calls only refresh matrices.
        self.poseLocalUpdates, self.poseWorldUpdates = 0, 0
        for _, root in ipairs(self.roots) do
            visit(self, root)
        end
        if self.objects then
            for _, o in ipairs(self.objects) do
                if o.skin then
                    require('./skinning').update(o)
                end
            end
        end
    end
end

return Rig

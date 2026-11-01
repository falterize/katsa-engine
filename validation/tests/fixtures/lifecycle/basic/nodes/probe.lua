local Probe = { base = 'Node3D' }
function Probe.register(world)
    world:registerNodeType('SceneProbe', Probe)
end
return Probe

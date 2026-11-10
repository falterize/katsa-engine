-- Inspector descriptions of particles, beams and trails.
-- Editor text only: the classes carry no hint of their own.
-- Shape: { ClassName = { property = 'text' } }; a subclass inherits its base class entries.
local Common = require('./common')

return {
    Beam3D = {
        attachment0 = 'Start of the beam: any Node3D (an Attachment3D is not required). The '
            .. 'curve leaves along its X axis.',
        attachment1 = 'End of the beam: any Node3D.',
        brightness = Common.shared.surfaceBrightness,
        curveSize0 = 'Distance of the first Bezier control point along attachment0 X axis.',
        curveSize1 = 'Distance of the second Bezier control point along attachment1 X axis.',
        faceCamera = 'On: the ribbon always turns its width toward the camera. Off: a flat '
            .. 'strip that keeps the orientation of its attachments.',
        lightInfluence = Common.shared.lightInfluence,
        maxDistance = Common.shared.renderRange,
        segments = 'Straight pieces the curve is cut into. A straight beam needs only 1.',
        texture = Common.shared.ribbonTexture,
        textureLength = 'World units covered by one image repeat (Wrap and Static).',
        width0 = 'Beam width at attachment0, in world units.',
        width1 = 'Beam width at attachment1, in world units.',
    },
    ParticleEmitter2D = {
        adornee = 'Optional emission support in the same World2D; ownership follows Parent.',
    },
    ParticleEmitter3D = {
        adornee = 'Independent emission support. None uses spatial Parent. Ownership and '
            .. 'cleanup still follow Parent.',
        attractionPoint = 'World-space target position, independent of emitter/parent rotation.',
        attractionSoftening = 'Positive world-unit radius: acceleration is strength / (1 + '
            .. '(distance/radius)^2).',
        attractionStrength = 'Acceleration at the target in world units/second squared, '
            .. 'softened with distance.',
        collisionEnabled = 'Optional point-segment physics raycasts, sharing a bounded update '
            .. 'budget. No rigid body per particle.',
        disabledBehavior = 'Drain: stop automatic births and let particles finish; Clear: '
            .. 'immediately remove existing particles.',
        drag = 'Per-second velocity relaxation toward wind; 0 gives no wind drag.',
        gravityScale = 'Dimensionless multiplier of the world-space gravity vector. 0 disables '
            .. 'gravity; negative values repel upward.',
        lifetime = 'Seconds: randomized Min / Max at birth.',
        lightInfluence = Common.shared.lightInfluence,
        liveCount = 'Current live particles. Runtime read-only.',
        maxDistance = 'World-unit render cutoff per particle; 0 disables it. OffscreenBehavior '
            .. 'controls simulation outside the camera view.',
        maxParticles = 'Birth cap, further limited by the shared MaxParticles budget. Existing '
            .. 'particles drain after lowering it.',
        offscreenBehavior = 'Pause stops simulation, births and collision queries outside the '
            .. 'camera view. Simulate preserves continuous offscreen physics. Existing world-space '
            .. 'particles also participate in visibility.',
        rate = 'Births per second, controlled directly by Rate.',
        shadowMaxParticles = 'Most particles that are written into the shadow maps per frame.',
        shapeSize = 'Full local X/Y/Z extents; cylinder/disc radii are half X/Z.',
        speed = 'Local units per second: Min / Max at birth.',
        spread = 'Cone half-angle in degrees, 0 to 180.',
        startSize = 'Full quad width/height in world units at birth, before sizeCurve.',
        useWorldGravity = 'Use Physics.gravity when present; otherwise use the emitter gravity '
            .. 'vector. Disable to author an independent field.',
    },
    Trail3D = {
        attachment0 = 'Single: the node the trail follows (empty = this Trail3D). Dual: top '
            .. 'edge. Any Node3D works, an Attachment3D is not required.',
        attachment1 = 'Dual mode only: bottom edge of the trail.',
        breakDistance = 'A jump longer than this (teleport) clears the trail instead of '
            .. 'stretching it. 0 disables.',
        brightness = Common.shared.surfaceBrightness,
        faceCamera = 'Dual mode: on turns the width toward the camera, off keeps the '
            .. 'orientation of the two nodes. Single mode always faces the camera.',
        lifetime = 'Seconds a point of the trail lives.',
        lightInfluence = Common.shared.lightInfluence,
        maxDistance = Common.shared.renderRange,
        maxLength = 'Longest path kept behind the head in world units; 0 is unlimited.',
        maxPoints = 'Hard cap on stored points (memory bound).',
        minLength = 'World units the node must move before a new point is stored. Larger values '
            .. 'give angular but cheaper trails.',
        texture = Common.shared.ribbonTexture,
        trailMode = 'Single: follow one node, always facing the camera. Dual: two nodes mark '
            .. 'the top and bottom of the trail (Roblox style).',
        width = 'Single mode: width of the trail in world units.',
    },
}

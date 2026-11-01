return function(test)
    local Inputs = require('source.engine.physics.3d.constraintInputs')
    local owner, a, b = {}, {}, {}
    local s = Inputs.begin(owner, a, b, 'test')
    s:number(1)
    local first = s:finish()
    s = Inputs.begin(owner, a, b, 'test')
    s:number(1.00000001)
    test:check(
        s:finish() == first,
        'Constraint input changes below prior five-decimal precision reuse the joint'
    )
    s = Inputs.begin(owner, a, b, 'test')
    s:number(1.1)
    test:check(s:finish() > first, 'Constraint input edits invalidate immediately')
    local Models = require('source.engine.import.models')
    local res = test.manager.resources:scope()
    local w = require('source.engine.world.world').new(res)
    local model = Models.load('assets/models/characters/xbot.glb', res)
    Models.instantiate(w, model, { name = 'DirtyProbe' })
    model:update(0)
    model:update(0)
    test:check(
        model.poseLocalUpdates == 0 and model.poseWorldUpdates == 0,
        'Unchanged skeleton skips TRS and hierarchy multiplication'
    )
    local leaf
    for _, node in ipairs(model.nodes) do
        if #node.children == 0 and not node.matrix then
            leaf = node
            break
        end
    end
    assert(leaf, 'No editable leaf in fixture')
    leaf.translation[1] = leaf.translation[1] + 0.25
    model:update(0)
    test:check(
        model.poseLocalUpdates == 1 and model.poseWorldUpdates == 1,
        'A leaf pose edit updates only its own matrices'
    )
    local old = leaf.world[4]
    leaf.world[4] = old + 20
    model:update(0)
    test:check(leaf.world[4] == old, 'External skeleton output edits are corrected')
    local skinObject
    for _, o in ipairs(model.objects) do
        if o.skin then
            skinObject = o
            break
        end
    end
    local Skin = require('source.engine.animation.skeleton.skinning')
    Skin.update(skinObject)
    Skin.update(skinObject)
    test:check(skinObject.skin.paletteReused, 'Unchanged skin palette reuses matrices and bounds')
    local m = skinObject.skin.matrices[1]
    local expected = m[4]
    m[4] = expected + 3
    Skin.update(skinObject)
    test:check(
        m[4] == expected and not skinObject.skin.paletteReused,
        'Edited palette outputs are repaired'
    )
    local bind = skinObject.skin.definition.inverseBindMatrices[skinObject.skin.palette[1] + 1]
    bind[4] = bind[4] + 0.1
    Skin.update(skinObject)
    test:check(not skinObject.skin.paletteReused, 'In-place inverse-bind edits invalidate palettes')
    w:release()
    res:release()
end

return function(test)
    local Node = require('source.engine.nodes')
    local Physics = require('source.engine.physics')
    local physics = Physics.new({ gravity = { 0, 0, 0 } })
    local root = Node.new('World3D', {})

    local function box(name, position)
        return Node.new('Mesh3D', { name = name, position = position, size = { 4, 4, 4 } }, root)
    end
    local ground = box('Ground', { 0, 0, 0 })
    local moving = box('Mover', { 0, 0, 0 })
    local groundBody = physics:addBody(ground, { type = 'Static' })
    local movingBody = physics:addBody(moving, { type = 'Dynamic' })
    local contacted, replacement = false, nil
    moving:connect('contactBegin', function()
        contacted = true
        moving:destroy()
        replacement = box('Replacement', { 20, 0, 0 })
        physics:addBody(replacement, { type = 'Dynamic' })
        test:check(
            movingBody.destroyed and physics._stepping and #physics.pendingRemoves == 1,
            'Contact destruction marks the body closed and queues solver removal'
        )
        test:check(
            not replacement.physics._inWorld and #physics.pendingAdds == 1,
            'Contact creation queues solver insertion'
        )
    end)
    for i = 1, 4 do
        physics:update(1 / 60)
    end
    test:check(contacted and moving.destroyed, 'Real Oimo contact permits node destruction')
    test:check(
        replacement and replacement.physics._inWorld and not movingBody._inWorld,
        'Solver membership changes commit after the step'
    )
    test:check(
        #physics.pendingAdds == 0 and #physics.pendingRemoves == 0 and #physics.bodies == 2,
        'Contact mutation queues drain without retained bodies'
    )
    -- Destroy a newly created body before it is ever inserted.
    local transient = box('Transient', { 40, 0, 0 })
    physics._stepping = true
    local transientBody = physics:addBody(transient, { type = 'Dynamic' })
    transient:destroy()
    physics._stepping = false
    physics:flushBodyChanges()
    test:check(
        transientBody.destroyed and not transientBody._inWorld and #physics.bodies == 2,
        'Create-then-destroy before insertion leaves no solver body'
    )
    physics:update(1 / 60)
    root:destroy()
    physics:release()
    test:check(
        #physics.bodies == 0 and groundBody.destroyed,
        'Scene shutdown removes contact-owned physics bodies'
    )
end

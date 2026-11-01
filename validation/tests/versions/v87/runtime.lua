local T = {}

local function extra(test)
    local scene = test.manager:switch(require('source.game.runtime.game').new, 'combined')
    local mesh = scene.world.byName['Cube10.2']
    local Reference = require('source.engine.core.valueSnapshot')
    local Properties = require('source.engine.graphics.pipeline.propertySnapshot')

    local function exercise(keys, vectors, edits)
        local expected, actual, context = {}, {}, { epoch = 0 }

        local function sample()
            context.epoch = context.epoch + 1
            assert(
                Reference.fields(expected, mesh, keys, vectors)
                    == Properties.fields(actual, mesh, keys, vectors, context),
                'Different change flags'
            )
            for _, list in ipairs({ keys, vectors or {} }) do
                for _, key in ipairs(list) do
                    local a, b = expected[key], actual[key]
                    if type(a) == 'table' then
                        assert(type(b) == 'table' and #a == #b)
                        for i = 1, #a do
                            assert(a[i] == b[i])
                        end
                    else
                        assert(a == b)
                    end
                end
            end
        end
        sample()
        sample()
        for _, edit in ipairs(edits) do
            edit()
            sample()
            sample()
        end
    end
    local unlit = mesh.unlit
    mesh.unlit = false
    exercise({ 'unlit' }, nil, {
        function()
            mesh.unlit = nil
        end,
        function()
            mesh.unlit = false
        end,
        function()
            mesh.unlit = true
        end,
        function()
            mesh.unlit = unlit
        end,
    })
    test:check(true, 'Direct scalar reads retain removal, false and replacement semantics')
    local color = mesh.color
    mesh._probeVector = { 1, 2, 3 }
    exercise({}, { '_probeVector' }, {
        function()
            mesh._probeVector[2] = 0.123
        end,
        function()
            mesh._probeVector = { 1, 2 }
        end,
        function()
            mesh._probeVector = { 1, 2, 3, 4 }
        end,
        function()
            mesh._probeVector = false
        end,
        function()
            mesh._probeVector = nil
        end,
        function()
            mesh._probeVector = nil
        end,
    })
    test:check(true, 'Direct vector reads retain mutation, resizing and fallback semantics')
end

function T.new(manager)
    local base = require('validation.tests.versions.v86.runtime').new(manager)
    local finish = base.finish
    base.finish = function(test)
        extra(test)
        finish(test)
        print('PASSED ' .. test.count .. ' v87 regression/integration checks')
    end
    return base
end

return T

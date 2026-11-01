local Test = {}

function Test.new()
    return {
        update = function()
            local Resources = require('source.engine.core.resources')
            local resources = Resources.new(require('source.game.data.manifest'))
            local source = 'assets/models/characters/xbot.glb'
            local model = require('source.engine.import.glb').load(source, resources)
            require('source.engine.import.packedModel').write(
                model,
                source,
                katsa.filesystem.getSource() .. '/' .. source .. '.kmesh'
            )
            resources:release()
            print('BAKED XBOT SIDECAR')
            katsa.event.quit()
        end,
        draw = function() end,
    }
end

return Test

local Previous = require('source.tests.versions.v107.preview')
local Preview = setmetatable({}, { __index = Previous })

function Preview.new(manager)
    local state = Previous.new(manager)
    if os.getenv('KATSA_PREVIEW_ORIENTATION') == '1' then
        state.scene.world.debug.orientation2D, state.scene.world.debug.orientation3D = true, true
        state.name = state.name .. '-axes'
    end
    return state
end

return Preview

local Observer = require('scene.scripts.behaviors.observer')
local System = {}
function System.create(state)
    return Observer.create(state, 'disabled')
end
return System

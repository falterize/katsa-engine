local Observer = require('scene.scripts.behaviors.observer')
local System = {}
function System.create(state)
    return Observer.create(state, 'alpha')
end
return System

-- The engine's tool windows, in menu order. A tool is { id, title, key?, new(), draw(ig, scene,
-- state, host) }; `new` returns the tool's private state.
return {
    require('./stats'),
    require('./debug'),
    require('./profiler'),
    require('./console'),
    require('./explorer'),
    require('./properties'),
}

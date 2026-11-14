local Codec = require('../codec')
local P = require('../protocol')
local Values = require('./values')

-- The three things the server tells a client about a replicated node, and how a batch is sent.
local Operations = {
    CREATE = 1,
    CHANGE = 2,
    REMOVE = 3,
}

-- ops: a list of { op, id, ... } tables. One reliable message per batch.
function Operations.send(player, ops)
    local writer = Codec.writer()
    writer:u8(P.NODES)
    writer:value(ops)
    player.link:send(writer:finish(), P.RELIABLE)
end

-- The CREATE operation for a node whose last sent state is `sent`.
function Operations.create(id, className, sent)
    return {
        op = Operations.CREATE,
        id = id,
        class = className,
        parent = sent.parent,
        name = sent.name,
        props = sent.props,
        attrs = sent.attrs,
    }
end

-- The CHANGE operation between two sent states, or nil when nothing differs.
function Operations.change(id, sent, state)
    local op = { op = Operations.CHANGE, id = id }
    local different = false
    if sent.name ~= state.name then
        op.name, different = state.name, true
    end
    if sent.parent ~= state.parent then
        op.parent, different = state.parent, true
    end
    local props = Values.diff(sent.props, state.props)
    if props then
        op.props, different = props, true
    end
    local attrs, removed = Values.diff(sent.attrs, state.attrs)
    if attrs or removed then
        op.attrs, op.removedAttrs, different = attrs, removed, true
    end
    return different and op or nil
end

return Operations

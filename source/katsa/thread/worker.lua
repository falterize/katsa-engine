-- The prelude every actor thread runs first, in its own Lua state. The host prepends the values it
-- owns: KATSA_ACTOR (address of the native actor), KATSA_LIB, KATSA_CDEF, KATSA_PATH / KATSA_CPATH,
-- KATSA_MODULES (name -> source), KATSA_ARGS (serialized), KATSA_SCRIPT and KATSA_SCRIPT_NAME.
--
-- The worker has no window, graphics, audio or scene: only the Lua standard library, LuaJIT's ffi,
-- the modules named in `modules`, and the global `Actor`:
--
--   Actor.args                     the table given to spawn
--   Actor.on(topic, fn)            handler: fn(data) -> result (the result answers a request)
--   Actor.send(topic, data)        message to the owner
--   Actor.poll(timeoutMs)          handle one message; true when one was handled
--   Actor.run()                    handle messages until the owner stops the actor (the default)
--   Actor.stopped()                true once the owner asked the actor to stop
--   Actor.sleep(ms), Actor.manual  set `Actor.manual = true` to run your own loop instead of run()
local ffi = require('ffi')
local buffer = require('string.buffer')

ffi.cdef(KATSA_CDEF)
package.path, package.cpath = KATSA_PATH, KATSA_CPATH
for name, source in pairs(KATSA_MODULES) do
    package.preload[name] = assert(loadstring(source, '=' .. name))
end

-- Workers load native libraries (image codecs ...) from the same folders as the owner.
do
    local Native = require('source.katsa.core.native')
    for index = #KATSA_LIBDIRS, 1, -1 do
        Native.addDirectory(KATSA_LIBDIRS[index])
    end
end

-- Same relative-require support as the main state, when the module is reachable.
do
    local ok, Relative = pcall(require, 'source.katsa.core.relativeRequire')
    if ok and Relative.wrap then
        require = Relative.wrap(require)
    end
end

local library = require('source.katsa.core.native').loadFile(KATSA_LIB)
-- Modules such as SharedArray find the library through the binding module; here it is already
-- loaded (and the C declarations exist), so hand over this instance.
package.loaded['source.katsa.thread.binding'] = {
    cdef = KATSA_CDEF,
    load = function()
        return library
    end,
}
local native = ffi.cast('KActor*', KATSA_ACTOR)
local handlers = {}
local dataPointer = ffi.new('const void*[1]')
local lengthPointer = ffi.new('size_t[1]')

Actor = { handlers = handlers, manual = false }
Actor.args = KATSA_ARGS ~= '' and buffer.decode(KATSA_ARGS) or {}

local function post(envelope)
    local bytes = buffer.encode(envelope)
    library.kt_send(native, 0, bytes, #bytes)
end

function Actor.send(topic, data)
    post({ topic = topic, data = data })
end

function Actor.on(topic, handler)
    handlers[topic] = handler
end

function Actor.stopped()
    return library.kt_stopped(native) ~= 0
end

function Actor.sleep(milliseconds)
    library.kt_sleep(milliseconds)
end

local function handle(envelope)
    local handler = handlers[envelope.topic] or Actor.onMessage
    if not handler then
        if envelope.id then
            post({ reply = envelope.id, error = 'No handler for ' .. tostring(envelope.topic) })
        end
        return
    end
    if envelope.id then
        local ok, result = pcall(handler, envelope.data, envelope.topic)
        if ok then
            post({ reply = envelope.id, data = result })
        else
            post({ reply = envelope.id, error = tostring(result) })
        end
    else
        local ok, message = pcall(handler, envelope.data, envelope.topic)
        if not ok then
            post({ topic = '$error', data = tostring(message) })
        end
    end
end

function Actor.poll(timeoutMs)
    local message = library.kt_recv(native, 1, timeoutMs or 0, dataPointer, lengthPointer)
    if message == nil then
        return false
    end
    local envelope = buffer.decode(ffi.string(dataPointer[0], lengthPointer[0]))
    library.kt_release(message)
    handle(envelope)
    return true
end

function Actor.run()
    while not Actor.stopped() do
        Actor.poll(-1)
    end
end

local chunk = assert(loadstring(KATSA_SCRIPT, '@' .. KATSA_SCRIPT_NAME))
chunk(Actor.args)
if not Actor.manual then
    Actor.run()
end

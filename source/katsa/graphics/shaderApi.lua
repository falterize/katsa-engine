-- Shader selection and creation (graphics.setShader / newShader).

local Shader = require('source.katsa.graphics.shader')
local Translator = require('source.katsa.graphics.shaderTranslator')
local State = require('source.katsa.graphics.state')
local S, stats, target = State.S, State.stats, State.target
local G = State.G

function G.setShader(shader)
    State.requireReady()
    if S.shader ~= shader then
        State.flush()
        stats.shaderswitches = stats.shaderswitches + 1
    end
    S.shader = shader
end

function G.getShader()
    return S.shader
end

function G.newShader(...)
    State.requireReady()
    return Shader.new(...)
end

function G.validateShader(gles, code, vertex)
    if type(gles) ~= 'boolean' then
        gles, code, vertex = false, gles, code
    end
    local source = code or vertex
    if gles then
        local FS = require('source.katsa.core.filesystem')
        if type(source) == 'string' and not source:find('\n', 1,
            true) and FS.getInfo(source, 'file') then
            source = FS.read(source)
        end
        local translated, message = Translator.translate(source, { target = 'es' })
        if not translated then
            return false, message
        end
        return true, ''
    end
    return Shader.validate(source)
end

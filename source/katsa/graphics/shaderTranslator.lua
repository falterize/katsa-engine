-- Translates the katsa shader dialect used by the engine into stage-specific GLSL.
--
-- Targets:
--   'desktop' -> #version 330 core
--   'es'      -> #version 300 es
--
-- One source holds both stages behind `#ifdef VERTEX` / `#ifdef PIXEL`, exactly like a katsa
-- shader. The translator adds the stage entry point, built-in uniforms and varyings, rewrites
-- `varying` / `attribute` / `extern`, and assigns explicit attribute locations so the native
-- vertex layout is known without querying the driver.
--
-- Built-in vertex attribute locations: VertexPosition 0, VertexTexCoord 1, VertexColor 2.
-- Custom `attribute` declarations follow in declaration order from location 3.
local Translator = {}

local targets = { desktop = true, es = true }

Translator.attributeLocations = { VertexPosition = 0, VertexTexCoord = 1, VertexColor = 2 }
Translator.firstCustomLocation = 3

local function stripComments(source)
    source = source:gsub('/%*.-%*/', function(block)
        return (block:gsub('[^\n]', ' '))
    end)
    return (source:gsub('//[^\n]*', ''))
end

local function glslDialect(source)
    local language = source:match('#%s*pragma%s+language%s+([%w]+)')
    return language or 'glsl1'
end

local function hasFunction(view, returnType, name)
    return view:find(returnType .. '%s+' .. name .. '%s*%(') ~= nil
end

local function typeOfAttribute(qualified)
    -- "highp vec4" / "vec3" -> "vec3"
    return qualified:match('([%w_]+)%s*$')
end

-- Rewrites `attribute` declarations and returns the new text plus the attribute table.
local function rewriteAttributes(source, report)
    local attributes, order = {}, {}
    local next_location = Translator.firstCustomLocation
    local text = source:gsub('([^\n]*)\n', function(line)
        local indent, qualifiers, name, suffix =
            line:match('^(%s*)attribute%s+([%w_%s]-)%s+([%w_]+)%s*(%b[]?)%s*;')
        if not name then
            indent, qualifiers, name = line:match('^(%s*)attribute%s+([%w_%s]-)%s+([%w_]+)%s*;')
            suffix = ''
        end
        if not name then
            return line .. '\n'
        end
        local builtin = Translator.attributeLocations[name]
        if builtin then
            local message = 'attribute %s redeclares a built-in attribute'
            report.errors[#report.errors + 1] = message:format(name)
            return line .. '\n'
        end
        local location = next_location
        next_location = next_location + 1
        local kind = typeOfAttribute(qualifiers)
        attributes[name] = { location = location, type = kind }
        order[#order + 1] = name
        return ('%slayout(location = %d) in %s %s;\n'):format(indent, location, qualifiers, name)
    end)
    return text, attributes, order
end

local function versionHeader(target)
    if target == 'es' then
        return table.concat({
            '#version 300 es',
            'precision highp float;',
            'precision highp int;',
            'precision highp sampler2D;',
            'precision highp sampler3D;',
            'precision highp samplerCube;',
            'precision highp sampler2DArray;',
        }, '\n')
    end
    return '#version 330 core'
end

local function commonMacros(dialect)
    local lines = {
        '#define number float',
        '#define Image sampler2D',
        '#define ArrayImage sampler2DArray',
        '#define CubeImage samplerCube',
        '#define VolumeImage sampler3D',
        '#define Texel texture',
        '#define extern uniform',
    }
    if dialect == 'glsl1' then
        lines[#lines + 1] = '#define texture2D texture'
        lines[#lines + 1] = '#define texture3D texture'
        lines[#lines + 1] = '#define textureCube texture'
    end
    return table.concat(lines, '\n')
end

local vertexBuiltins = table.concat({
    'layout(location = 0) in vec4 VertexPosition;',
    'layout(location = 1) in vec4 VertexTexCoord;',
    'layout(location = 2) in vec4 VertexColor;',
    'uniform highp mat4 TransformMatrix;',
    'uniform highp mat4 ProjectionMatrix;',
    'uniform highp mat4 TransformProjectionMatrix;',
    'uniform highp mat3 NormalMatrix;',
    'uniform highp vec4 ConstantColor;',
    'uniform highp float katsa_PointSize;',
    'uniform highp vec4 katsa_ScreenSize;',
    '#define katsa_VertexID gl_VertexID',
    '#define katsa_InstanceID gl_InstanceID',
    '#define varying out',
}, '\n')

local pixelBuiltins = table.concat({
    'uniform highp vec4 katsa_ScreenSize;',
    'uniform sampler2D MainTex;',
    '#define varying in',
    'highp vec2 katsa_PixelCoord(highp vec2 fragment) {',
    '    return vec2(fragment.x, fragment.y * katsa_ScreenSize.z + katsa_ScreenSize.w);',
    '}',
}, '\n')

local defaultPosition = 'vec4 position(mat4 transformProjection, vec4 vertexPosition) {\n'
    .. '    return transformProjection * vertexPosition;\n}'
local defaultEffect = 'vec4 effect(vec4 color, Image tex, vec2 textureCoords, '
    .. 'vec2 screenCoords) {\n'
    .. '    return Texel(tex, textureCoords) * color;\n}'

local effectCall = 'effect(VaryingColor, MainTex, VaryingTexCoord.st, '
    .. 'katsa_PixelCoord(gl_FragCoord.xy));'

local vertexMain = table.concat({
    'out vec4 VaryingTexCoord;',
    'out vec4 VaryingColor;',
    'void main() {',
    '    VaryingTexCoord = VertexTexCoord;',
    '    VaryingColor = VertexColor * ConstantColor;',
    '    gl_PointSize = katsa_PointSize;',
    '    gl_Position = position(TransformProjectionMatrix, VertexPosition);',
    '}',
}, '\n')

local function pixelMain(targets)
    local outputs
    if targets > 1 then
        outputs = ('layout(location = 0) out vec4 katsa_Canvases[%d];'):format(targets)
    else
        outputs = 'layout(location = 0) out vec4 katsa_PixelColor;'
    end
    local target = targets > 1 and 'katsa_Canvases[0]' or 'katsa_PixelColor'
    return table.concat({
        'in vec4 VaryingTexCoord;',
        'in vec4 VaryingColor;',
        outputs,
        'void main() {',
        '    ' .. target .. ' = ' .. effectCall,
        '}',
    }, '\n')
end

-- options.target: 'desktop' (default) or 'es'
-- options.renderTargets: number of simultaneous pixel outputs (default 1)
-- Returns { vertex, pixel, attributes, attributeOrder, dialect } or nil, message.
function Translator.translate(source, options)
    options = options or {}
    local target = options.target or 'desktop'
    if not targets[target] then
        return nil, 'Unknown shader target: ' .. tostring(target)
    end
    if type(source) ~= 'string' or source == '' then
        return nil, 'Shader source is empty'
    end
    local dialect = glslDialect(source)
    if dialect ~= 'glsl1' and dialect ~= 'glsl3' then
        return nil, 'Unsupported shader language: ' .. dialect
    end
    local bare = source:gsub('#%s*pragma%s+language%s+[%w]+', '')
    local report = { errors = {} }
    local result = { dialect = dialect, target = target }
    local renderTargets = options.renderTargets or 1
    if bare:find('katsa_Canvases', 1, true) then
        renderTargets = math.max(renderTargets, options.renderTargets or 4)
    end

    local stripped = stripComments(bare)
    -- Same rule for every stage: user code goes to the stage(s) whose entry point it defines.
    local userVertex = hasFunction(stripped, 'vec4', 'position')
    local userPixel = hasFunction(stripped, 'vec4', 'effect')
    if not userVertex and not userPixel then
        return nil, 'Shader must define vec4 position(...) or vec4 effect(...)'
    end
    local header = versionHeader(target)
    local macros = commonMacros(dialect)

    local rewritten, attributes, order = rewriteAttributes(bare .. '\n', report)
    if #report.errors > 0 then
        return nil, table.concat(report.errors, '; ')
    end
    result.attributes, result.attributeOrder =
        userVertex and attributes or {}, userVertex and order or {}

    local function assemble(builtins, define, user, tail)
        return table.concat({
            header,
            '#define ' .. define .. ' 1',
            macros,
            builtins,
            '#line 1',
            user or '',
            tail,
        }, '\n')
    end

    local vertexTail = defaultPosition .. '\n' .. vertexMain
    if userVertex then
        vertexTail = vertexMain
    end
    local pixelTail = defaultEffect .. '\n' .. pixelMain(renderTargets)
    if userPixel then
        pixelTail = pixelMain(renderTargets)
    end
    local vertexUser = userVertex and rewritten or nil
    local pixelUser = userPixel and (bare .. '\n') or nil
    result.vertex = assemble(vertexBuiltins, 'VERTEX', vertexUser, vertexTail)
    result.pixel = assemble(pixelBuiltins, 'PIXEL', pixelUser, pixelTail)
    result.renderTargets = renderTargets
    return result
end

return Translator

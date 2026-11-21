-- Shader programs: user shaders in the spatial world, shadow, particle and canvas programs,
-- material draw modes, uniform defaults and error reporting.
local Application = require('source.runtime.application')
local Programs = require('source.engine.graphics.shaders.programs')
local Material = require('source.engine.graphics.materials.material')

local Module = {}

local fixtures = 'validation/tests/fixtures/shaders/'

function Module.run(self)
    local displace = Programs.parse(fixtures .. 'displace.glsl', 'spatial')
    local toon = Programs.parse(fixtures .. 'toon.glsl', 'spatial')
    local modes = Programs.parse(fixtures .. 'modes.glsl', 'spatial')

    local world, program = Programs.compile('assets/shaders/engine/world.glsl', {
        shaders = { displace, toon },
    })
    self:check(
        world:hasUniform('s1_amplitude') and world:hasUniform('s1_glow'),
        'A user shader compiles into the world program with namespaced uniforms'
    )
    self:check(
        program.defaults.s1_amplitude == 0.25 and #program.defaults.s1_glow == 3,
        'Uniform defaults come from the shader file'
    )
    self:check(
        program.flags.KATSA_USER_VERTEX and program.flags.KATSA_USER_FRAGMENT
            and program.flags.KATSA_USER_LIGHT and program.flags.KATSA_USER_PBR,
        'vertex(), fragment(), light() and ROUGHNESS use are detected'
    )
    local shadow = Programs.compile('assets/shaders/engine/shadow.glsl', {
        shaders = { displace },
        entries = { vertex = true },
    })
    self:check(shadow:hasUniform('s1_amplitude'), 'The shadow program runs the user vertex()')
    local sprite = Programs.compile('assets/shaders/engine/particles/sprite.glsl', {
        shaders = { displace },
        entries = { vertex = true, fragment = true },
    })
    self:check(sprite:hasUniform('s1_glow'), 'The particle program runs the user fragment()')

    local sky = Programs.parse(fixtures .. 'sky.glsl', 'sky')
    local fog = Programs.parse(fixtures .. 'fog.glsl', 'fog')
    local skyProgram = Programs.compile('assets/shaders/engine/skyShader.glsl', {
        kind = 'sky',
        shaders = { sky },
        entries = { fragment = true },
    })
    self:check(
        skyProgram:hasUniform('s1_horizon') and skyProgram:hasUniform('right'),
        'A sky shader compiles into the sky template with the shared ray uniforms'
    )
    local fogProgram = Programs.compile('assets/shaders/engine/post/volumetricFog.glsl', {
        kind = 'fog',
        shaders = { fog },
        entries = { fragment = true },
    })
    self:check(
        fogProgram:hasUniform('s1_strength') and fogProgram:hasUniform('stepCount'),
        'A fog shader compiles into the volumetric fog pass'
    )
    self:check(
        not pcall(Programs.parse, fixtures .. 'sky.glsl', 'spatial'),
        'A sky shader cannot be used as a mesh shader'
    )

    local resources = self.manager.resources:scope()
    local material = Material.new(resources, { shaders = { modes } })
    self:check(
        material.blend == 'add' and material.cull == 'none' and material.depthWrite == false,
        'render_mode blend, cull and depth modes reach the material'
    )
    self:check(
        material.castsShadow == false and material.shadowShader == nil,
        'shadows_disabled builds no shadow program'
    )

    local ok, message = pcall(
        Programs.compile,
        'assets/shaders/engine/world.glsl',
        {
            shaders = {
                Programs.parseText(
                    'shader_type spatial;\nvoid fragment() {\n    ALBEDO = nope;\n}\n',
                    'broken.glsl'
                ),
            },
        }
    )
    self:check(
        not ok and tostring(message):find('broken.glsl:3', 1, true),
        'A compile error names the user file and line'
    )

    local scene = Application.new(self.manager, 'models')
    scene:load()
    scene:update(1 / 60, 1 / 60)
    local target = scene.world.objects[1]
    local node = scene.world:create('Shader3D', {
        shaderPath = fixtures .. 'displace.glsl',
        uniforms = { amplitude = 0.5 },
    }, target)
    scene.renderer.world = scene.world
    local resolved = require('source.engine.graphics.shaders.materialResolver').resolve(
        scene.world,
        target
    )
    self:check(
        resolved and resolved.uniforms.s1_amplitude == 0.5 and resolved.uniforms.s1_glow ~= nil,
        'Shader3D uniforms override the declared defaults'
    )
    node.uniforms.unknown = 1
    scene.world._shaderMaterials = nil
    target._shaderStackSignature = nil
    self:check(
        not pcall(
            require('source.engine.graphics.shaders.materialResolver').resolve,
            scene.world,
            target
        ),
        'A Shader3D uniform the file does not declare is rejected'
    )
    scene:release()
end

return Module

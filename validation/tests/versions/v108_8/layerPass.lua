-- Shader2D viewLayers: a render of only some layer groups for hint_layer_texture.
local Application = require('game.runtime.application')
local LayerPass = require('source.engine.graphics.pipeline.layerPass')

local Module = {}

function Module.run(self)
    local scene = Application.new(self.manager, 'stareShooter')
    scene:load()
    local registry = scene.world.layerGroups
    local outlined = registry.bits.Outlined
    self:check(
        LayerPass.mask(scene.world, 'Outlined') == outlined
            and LayerPass.mask(scene.world, { 'Outlined', 'Player' }) == outlined + registry.bits.Player
            and LayerPass.mask(scene.world, '') == nil,
        'viewLayers names become the bit mask of those groups (a string or a table)'
    )
    self:check(not pcall(LayerPass.mask, scene.world, 'NoSuchGroup'), 'An unknown layer group in viewLayers is an error')

    local effect = scene.demo.outline
    self:check(effect.viewLayers == 'Outlined', 'The outline shader sees the Outlined group')

    effect.enabled = true
    for _ = 1, 3 do
        scene:update(1 / 60, 1 / 60)
        scene:draw()
    end
    local passes = scene._ui._layerPasses
    local pass = passes and passes[outlined]
    self:check(
        pass and pass.color and pass.renderer.layerPass and pass.renderer.shadows == scene.renderer.shadows,
        'The layer pass renders once for the mask and shares the main shadow atlas'
    )
    self:check(pass.renderer.density <= scene.renderer.density * 0.5 + 1e-6, 'The layer pass runs at half the main density')
    scene:release()
end

return Module

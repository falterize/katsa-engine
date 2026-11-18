-- Brings an outside file into the level. The file is copied into the level's assets (scene) or,
-- for a project file under assets/, referenced as shared://. A model is placed, an image becomes
-- a sprite quad or the colour map of the selected mesh, anything else (audio, fonts, data) is
-- copied and reported so it can be used from scripts.
local AssetStore = require('../io.assetStore')
local Clone = require('source.engine.nodes.core.clone')
local Models = require('source.engine.import.models')

local Importer = {}

-- Where `path` ends up and what it is: the store path (or shared:// URL) and the file kind.
function Importer.store(state, path)
    local kind = AssetStore.kind(path, Models.supports)
    local relative = path:match('^assets/(.+)$')
    if state.importTarget == 'shared' and relative then
        return 'shared://' .. relative, kind
    end
    if state.importTarget == 'shared' then
        state:notify('Shared needs a file under assets/; it was copied into the scene folder instead')
    end
    return AssetStore.import(path, Models.supports)
end

-- action: 'add' (model), 'sprite' (image as a quad), 'texture' (image on the selected mesh) or
-- nil to pick by file type. `slot` spreads several files side by side. Returns true on success.
function Importer.import(state, path, action, slot)
    local stored, kind = Importer.store(state, path)
    if not stored then
        state:notify(tostring(kind))
        return false
    end
    local position = state:placement()
    local x = position[1] + (slot or 0) * 3
    if kind == 'model' and (action == nil or action == 'add') then
        local ok, message = pcall(state.ops.placeModel, state.ops, stored, { x, position[2], position[3] })
        if not ok then
            state:notify('Cannot load the model: ' .. tostring(message))
        end
        return ok
    elseif kind == 'image' and (action == nil or action == 'sprite') then
        local mesh = state.ops:create('Mesh3D', {
            name = Clone.uniqueName(state.world, 'Sprite'),
            kind = 'quad',
            position = { x, position[2] + 1, position[3] },
            size = { 2, 2, 1 },
        })
        state.ops:applyTexture(mesh, stored)
        return true
    elseif kind == 'image' and action == 'texture' then
        local target = state.selection:primary()
        if target and target.className == 'Mesh3D' then
            state.ops:applyTexture(target, stored)
            return true
        end
        state:notify('Select a mesh to texture')
        return false
    elseif action == nil or action == 'file' then
        state:notify(('Imported %s: %s'):format(kind, stored))
        return true
    end
    state:notify('That action does not fit this file type')
    return false
end

-- Several files at once (the native dialog, drag and drop).
function Importer.many(state, paths)
    local done = 0
    for index, path in ipairs(paths) do
        if Importer.import(state, path, nil, index - 1) then
            done = done + 1
        end
    end
    if #paths > 1 then
        state:notify(('Imported %d of %d files'):format(done, #paths))
    end
    return done
end

-- Opens the system file dialog; falls back to the in-app browser when there is none.
function Importer.dialog(state)
    local paths, reason = katsa.system.openFileDialog({
        title = 'Import assets',
        multiple = true,
        filters = {
            { 'All files', '*' },
            { 'Models', 'glb;gltf;obj;blend' },
            { 'Images', 'png;jpg;jpeg;bmp;tga' },
            { 'Audio', 'wav;ogg;mp3;flac' },
        },
    })
    if not paths then
        state:notify(tostring(reason or 'No file dialog here') .. ' - use the file browser')
        state.panels.browser:show('Files')
        return
    end
    Importer.many(state, paths)
end

return Importer

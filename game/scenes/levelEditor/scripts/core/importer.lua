-- Brings outside files into the level. An import only COPIES the file into the level's own files
-- (the folder the Assets tab is showing, else a folder by file type) and shows where it went;
-- placing it in the scene is a separate step (Add to level, Use as texture), so nothing appears
-- in the level that the author did not ask for. Project files can also be used in place
-- (shared://) without a copy.
local AssetStore = require('../io.assetStore')
local Clone = require('source.engine.nodes.core.clone')
local LevelFiles = require('../io.levelFiles')
local Models = require('source.engine.import.models')

local Importer = {}

-- Copies `path` into the level files. `folder` is relative to the assets root; nil picks a folder
-- by file type. Returns the store path and the file kind, or nil plus a message.
function Importer.copy(path, folder)
    local kind = AssetStore.kind(path, Models.supports)
    local relative, message = LevelFiles.importFile(path, folder or LevelFiles.folderFor(kind))
    if not relative then
        return nil, message
    end
    return LevelFiles.full(relative), kind
end

-- A stored asset (store path or shared:// URL) placed in the level. action: 'add' (model),
-- 'sprite' (image as a quad), 'texture' (image on the selected mesh) or nil to pick by type.
function Importer.place(state, stored, kind, action, slot)
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
        if target and (target.className == 'Mesh3D' or target.className == 'Decal3D') then
            state.ops:applyTexture(target, stored)
            return true
        end
        state:notify('Select a mesh or a decal to put the image on')
        return false
    end
    state:notify('A ' .. tostring(kind) .. ' cannot be placed in the scene; use it from scripts')
    return false
end

-- Several files at once (the file dialog, drag and drop): copied into the folder the Assets tab
-- shows, then revealed there. Returns how many were copied.
function Importer.many(state, paths)
    local browser = state.panels.browser
    local folder = browser and browser:importFolder()
    local done, last = 0, nil
    for _, path in ipairs(paths) do
        local stored, result = Importer.copy(path, folder)
        if stored then
            done, last = done + 1, stored
        else
            state:notify(tostring(result))
        end
    end
    if last and browser then
        browser:reveal(last, done)
    end
    return done
end

-- Opens the system file dialog; falls back to the Assets tab when there is none.
function Importer.dialog(state)
    local paths, reason = katsa.system.openFileDialog({
        title = 'Import assets into the level files',
        multiple = true,
        filters = {
            { 'All files', '*' },
            { 'Models', 'glb;gltf;obj;blend' },
            { 'Images', 'png;jpg;jpeg;bmp;tga' },
            { 'Audio', 'wav;ogg;mp3;flac' },
        },
    })
    if not paths then
        state:notify(tostring(reason or 'No file dialog here') .. ' - copy files into the level folder shown in Assets, or drop them on the window')
        state.panels.browser:openAssets()
        return
    end
    Importer.many(state, paths)
end

return Importer

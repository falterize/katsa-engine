-- Test helper: whether the scene shows its engine navigation (the ImGui toolbar when it replaces
-- the legacy header, else the header itself).
local Navigation = {}

function Navigation.visible(scene)
    local editor = scene:module('editor')
    if editor and editor.imgui then
        return not editor.imgui.hidden
    end
    return scene.navigation.visible
end

return Navigation

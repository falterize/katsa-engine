local function hasWorldCamera(scene)
    return scene.world and scene.world.activeCamera and scene.camera and not scene.camera.destroyed
end

local function visualPanelAt(scene, board, x, y)
    if not hasWorldCamera(scene) or not board.canvas or not board.drawable or board.destroyed then
        return false
    end
    local bx, by, depth = board:localPoint(x, y)
    local bounds = board.bounds
    if
        not bx
        or bounds and (bx < bounds[1] or by < bounds[2] or bx > bounds[3] or by > bounds[4])
    then
        return false
    end
    if not board.onTop and scene.world:occluded(scene.camera, x, y, depth) then
        return false
    end
    return board.ui:blocksWorldClick(bx, by)
end
return { hasWorldCamera = hasWorldCamera, visualPanelAt = visualPanelAt }

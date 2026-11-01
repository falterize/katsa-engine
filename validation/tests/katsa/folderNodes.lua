-- A scene node can be a folder: nodes/<name>/init.lua plus sibling modules.
return function(T)
    local ok, Package = pcall(require, 'source.engine.scenes.package')
    if not ok or not rawget(_G, 'katsa') then
        return T.skip('folderNodes: scene package needs the global katsa (' .. tostring(Package) .. ')')
    end
    katsa.filesystem.setSource('.')
    local opened, package = pcall(Package.open, 'source/game/scenes/multiplayerCars')
    if not opened then
        return T.skip('folderNodes: scene folder not readable (' .. tostring(package) .. ')')
    end
    local car = package:require('nodes.vehicle')
    T.check(car.base == 'Mesh3D' and car.Model and car.Collision and car.Deformation,
        'folderNodes: nodes/vehicle/init.lua loads its model, collision and deformation parts')
    T.check(package:require('nodes.vehicle.model') == car.Model,
        'folderNodes: parts are shared through the module cache')
    local single = package:require('settings')
    T.check(single.nodes[1] == 'vehicle', 'folderNodes: a plain file module still loads')
    T.check(package.compatibility.status == 'same', 'folderNodes: scene declares the running engine version')
    package:release()

    local Version = require('source.engine.core.version')
    T.check(Version.compatible('v108.3', 'v108.4') == 'older', 'version: earlier minor is older')
    T.check(Version.compatible('v109', 'v108.4') == 'newer', 'version: later major is newer')
    T.check(Version.compatible('v108.4', 'v108.4') == 'same', 'version: equal versions match')
    T.check(Version.compatible(nil) == 'unknown' and Version.compatible('abc') == 'unknown',
        'version: missing or invalid declarations are unknown')
    T.check(Version.compare('v9.10', 'v9.9') == 1, 'version: minor compares numerically')
end

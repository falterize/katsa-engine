-- A scene node can be a folder: nodes/<name>/init.lua plus sibling modules.
return function(T)
    local ok, Package = pcall(require, 'source.engine.scenes.package')
    if not ok or not rawget(_G, 'katsa') then
        return T.skip(
            'folderNodes: scene package needs the global katsa (' .. tostring(Package) .. ')'
        )
    end
    katsa.filesystem.setSource('.')
    local opened, package = pcall(Package.open, 'source/game/scenes/multiplayerCars')
    if not opened then
        return T.skip('folderNodes: scene folder not readable (' .. tostring(package) .. ')')
    end
    local car = package:require('nodes.vehicle')
    T.check(
        car.base == 'Mesh3D' and car.Model and car.Collision and car.Deformation,
        'folderNodes: nodes/vehicle/init.lua loads its model, collision and deformation parts'
    )
    T.check(
        package:require('nodes.vehicle.model') == car.Model,
        'folderNodes: parts are shared through the module cache'
    )
    local single = package:require('settings')
    T.check(single.nodes[1] == 'vehicle', 'folderNodes: a plain file module still loads')
    T.check(
        package.compatibility.status == 'same',
        'folderNodes: scene declares the running engine version'
    )
    package:release()

    local Version = require('source.engine.core.version')
    T.check(Version.compatible('0.9.0', '1.0.0a') == 'older', 'version: earlier number is older')
    T.check(Version.compatible('1.0.0', '1.0.0a') == 'newer', 'version: stable is newer than alpha')
    T.check(Version.compatible('1.0.0a', '1.0.0b') == 'older', 'version: alpha is older than beta')
    T.check(Version.compatible('1.0.0a', '1.0.0a') == 'same', 'version: equal versions match')
    T.check(Version.compatible('2', '1.9.9') == 'newer', 'version: short forms parse')
    T.check(
        Version.compatible(nil) == 'unknown'
            and Version.compatible('abc') == 'unknown'
            and Version.compatible('1.0.0x') == 'unknown',
        'version: missing or invalid declarations are unknown'
    )
    T.check(Version.compare('1.10.0', '1.9.0') == 1, 'version: numbers compare numerically')
end

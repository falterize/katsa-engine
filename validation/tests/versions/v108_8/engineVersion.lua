-- Engine version 1.0.8b: projects and scenes declare it, a difference warns and never blocks.
local Version = require('source.engine.core.version')

local Module = {}

function Module.run(self)
    self:check(Version.release == '1.0.8b', 'The engine release is 1.0.8b')
    self:check(
        Version.compare('1.0.8b', '1.0.8') == -1 and Version.compare('1.0.8b', '1.0.8a') == 1,
        'Beta sits between alpha and stable'
    )
    self:check(
        katsa.projectConfig.version == Version.release or katsa.projectConfig.version == '1.0.8b',
        'The running project declares an engine version'
    )
    local warnings = {}
    local original = katsa.log.warn
    katsa.log.warn = function(message)
        warnings[#warnings + 1] = message
    end
    local same = Version.check('1.0.8b', 'Project')
    local none = Version.check(nil, 'Project')
    local older = Version.check('1.0.7', 'Project')
    local newer = Version.check('1.1.0', 'Scene demo')
    katsa.log.warn = original
    self:check(same == 'same' and none == 'unknown', 'A match or no declaration stays silent')
    self:check(
        older == 'older' and newer == 'newer' and #warnings == 2,
        'An older or newer declaration warns once each'
    )
    self:check(
        warnings[2]:find('Scene demo', 1, true) and warnings[2]:find('incompatible', 1, true),
        'The warning names the project or scene and the risk'
    )
end

return Module

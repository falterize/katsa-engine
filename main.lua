local Bootstrap = require('source.engine.scenes.bootstrap')
local Optional = require('source.runtime.optional')

-- A game folder supplies its own main.lua; this one runs the engine alone. The examples mounted
-- for the tests provide `game.data.project`, otherwise the engine's empty project is used.
local project = Optional.require('game.data.project') or require('source.runtime.project')
require('source.runtime.catalog').use(project.catalog)
Bootstrap.install(project, require('source.runtime.startup'))

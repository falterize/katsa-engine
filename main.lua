local Bootstrap = require('source.engine.scenes.bootstrap')

-- A game folder supplies its own main.lua; this one runs the engine alone (or a project or scene
-- over it). The settings come from the conf.lua the program started with.
Bootstrap.install(require('source.runtime.startup'))

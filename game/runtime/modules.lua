-- Optional scene modules per runtime (see source/engine/scenes/modules.lua). Each entry is a
-- module under game/. Delete a line, and the folder it names, to build without that feature; the
-- engine and the scenes keep working because they only reach modules through `scene:module(name)`
-- and the hooks.
return {
    -- The full runtime: the demonstration runtime for the example scenes.
    game = {
        'game.devtools.overlay',
        'game.devtools.navigation',
        'game.devtools.editor',
    },
    -- The standalone host of independent games: only the Stats and Console overlays.
    standalone = {
        'game.devtools.overlay',
    },
}

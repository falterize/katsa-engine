-- Editor UI entry, laid out like the Godot editor: a menu bar and a tool strip on top, the Workspace tree on the
-- left, the Properties inspector on the right, a dock with tabs (Create, Files, Location) under
-- the viewport and a status bar. Every dock edge is a draggable splitter. Look and colours come
-- from the uiStyler style sheet (assets/styles/editor.lua) and the theme in Settings.
local Browser = require('./panels.browser')
local Dock = require('./dock')
local Kit = require('./kit')
local Menubar = require('./panels.menubar')
local Prompt = require('./panels.prompt')
local Properties = require('./panels.properties')
local Settings = require('./panels.settings')
local Toolbar = require('./panels.toolbar')
local Tree = require('./panels.tree')

local Interface = {}

local function styler(state, ui)
    local scene = state.scene
    local node = scene.world:create('UIStyler', {
        name = 'UIStyler',
        theme = state.prefs.theme,
        stylesFolder = 'scene://styles',
    })
    state.stylerNode, state.styler = node, node:bind(ui, scene.resources)
end

function Interface.create(state)
    local ui = state.scene.root:find('World3D/World2D')
    styler(state, ui)

    local function frame(name, z, ...)
        return Kit.make(ui, 'Frame', { name = name, zIndex = z }, ui.content, ...)
    end
    local frames = {
        view = state.viewport,
        top = frame('Toolbar', 6, 'bar'),
        left = frame('WorkspacePanel', 5, 'dock'),
        right = frame('PropertiesPanel', 5, 'dock'),
        bottom = frame('BrowserPanel', 5, 'dock'),
        status = frame('StatusBar', 6, 'bar'),
    }
    for _, name in ipairs({ 'splitLeft', 'splitRight', 'splitBottom' }) do
        frames[name] = Kit.make(ui, 'Button', { name = name, zIndex = 7 }, ui.content, 'splitter')
    end

    state.panels = {}
    state.panels.menubar = Menubar.create(state, ui, frames.top)
    state.panels.toolbar = Toolbar.create(state, ui, frames.top)
    state.panels.tree = Tree.create(state, ui, frames.left)
    state.panels.properties = Properties.create(state, ui, frames.right)
    state.panels.browser = Browser.create(state, ui, frames.bottom)
    state.status = Kit.label(ui, frames.status, '', {
        name = 'Status',
        position = { 0, 10, 0, 2 },
        size = { 1, -20, 1, -4 },
    }, 'text')
    state.marqueeFrame = Kit.make(ui, 'Frame', { name = 'Marquee', zIndex = 30, visible = false, interactable = false }, ui.content, 'marquee')
    state.dock = Dock.new(state, ui, frames, state.prefs.layout)
    state.panels.settings = Settings.create(state, ui)
    state.panels.prompt = Prompt.create(state, ui)
    state.dock:apply()
    state.styler:apply(ui.content)
end

return Interface

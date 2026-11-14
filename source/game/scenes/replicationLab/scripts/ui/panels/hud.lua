-- The round banner and the scoreboard. Both only read replicated nodes: the `Round` node's
-- attributes and the `Players` folder; nothing here is sent anywhere.
local Hud = {}
Hud.__index = Hud

local STATE_COLORS = {
    Intermission = { 0.55, 0.75, 1 },
    Playing = { 0.45, 0.95, 0.5 },
    Results = { 1, 0.85, 0.35 },
}

function Hud.create(ui, session)
    local self = setmetatable({ session = session }, Hud)
    self.banner = ui:text({
        name = 'RoundBanner',
        position = { 0.5, 0, 0, 14 },
        size = { 0, 560, 0, 70 },
        anchorPoint = { 0.5, 0 },
        text = 'Connecting...',
        fontSize = 26,
        backgroundColor = { 0.04, 0.07, 0.11 },
        backgroundTransparency = 0.35,
        interactable = false,
    }, ui.content)
    self.board = ui:text({
        name = 'Scoreboard',
        position = { 1, -16, 0, 16 },
        size = { 0, 240, 0, 220 },
        anchorPoint = { 1, 0 },
        text = '',
        fontSize = 18,
        align = 'left',
        verticalAlign = 'top',
        backgroundColor = { 0.04, 0.07, 0.11 },
        backgroundTransparency = 0.35,
        interactable = false,
    }, ui.content)
    return self
end

local function scoreLines(folder)
    local rows = {}
    for _, node in ipairs(folder.children) do
        rows[#rows + 1] = { node:getAttribute('Nickname') or node.name, node:getAttribute('Score') or 0 }
    end
    table.sort(rows, function(a, b)
        if a[2] ~= b[2] then
            return a[2] > b[2]
        end
        return a[1] < b[1]
    end)
    local lines = { 'Score' }
    for _, row in ipairs(rows) do
        lines[#lines + 1] = ('%s  %d'):format(row[1], row[2])
    end
    return table.concat(lines, '\n')
end

function Hud:update()
    local round, players = self.session:node('Round'), self.session:node('Players')
    if round then
        local state = round:getAttribute('State') or ''
        self.banner.text = ('%s  %ds\n%s'):format(
            state,
            round:getAttribute('Timer') or 0,
            round:getAttribute('Message') or ''
        )
        self.banner.textColor = STATE_COLORS[state] or { 1, 1, 1 }
    end
    if players then
        self.board.text = scoreLines(players)
    end
end

return Hud

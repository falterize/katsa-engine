-- What runs when there is nothing to start: a black screen and a console message. When a project
-- holds several scenes but names no start scene, the same screen lists them to pick one.
local Empty = {}
Empty.__index = Empty

local MESSAGE = 'No scene to run. Start katsa with a scene or project folder/archive, '
    .. 'or drop one on the window: katsa <path>'

function Empty.new(manager, options)
    options = options or {}
    local self = setmetatable({
        manager = manager,
        scenes = options.scenes or {},
        open = options.open,
        selected = 1,
        settings = {},
    }, Empty)
    if #self.scenes == 0 then
        katsa.log.write('warn', MESSAGE, 'scene')
    end
    return self
end

function Empty:draw()
    if #self.scenes == 0 then
        return
    end
    local graphics = katsa.graphics
    local lineHeight = 24
    graphics.setColor(1, 1, 1)
    graphics.print('Choose a scene (Up/Down, Enter or click):', 24, 20)
    for index, scene in ipairs(self.scenes) do
        local y = 56 + (index - 1) * lineHeight
        if index == self.selected then
            graphics.setColor(0.35, 0.65, 1)
        else
            graphics.setColor(0.8, 0.8, 0.8)
        end
        graphics.print(scene.id, 40, y)
    end
    graphics.setColor(1, 1, 1)
end

function Empty:keypressed(key)
    local count = #self.scenes
    if count == 0 then
        return
    elseif key == 'up' then
        self.selected = (self.selected - 2) % count + 1
    elseif key == 'down' then
        self.selected = self.selected % count + 1
    elseif key == 'return' or key == 'kpenter' then
        self.open(self.scenes[self.selected])
    end
end

function Empty:pointerpressed(_, x, y)
    local index = math.floor((y - 56) / 24) + 1
    if x >= 24 and self.scenes[index] then
        self.selected = index
        self.open(self.scenes[index])
    end
end

return Empty

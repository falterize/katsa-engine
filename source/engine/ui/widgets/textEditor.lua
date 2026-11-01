local utf8 = require('utf8')
local Editor = {}
Editor.__index = Editor

local function previous(text, at)
    return at > 0 and (utf8.offset(text, -1, at + 1) or 1) - 1 or 0
end

local function following(text, at)
    return at < #text and (utf8.offset(text, 2, at + 1) or #text + 1) - 1 or #text
end

function Editor.new(text)
    local self = setmetatable({ undo = {}, redo = {} }, Editor)
    self:set(text or '')
    return self
end

function Editor:set(text, selectAll)
    self.text, self.cursor = text, #text
    self.anchor = selectAll and 0 or self.cursor
    self.undo, self.redo = {}, {}
end

function Editor:range()
    return math.min(self.cursor, self.anchor), math.max(self.cursor, self.anchor)
end

function Editor:selected()
    local a, b = self:range()
    return self.text:sub(a + 1, b)
end

function Editor:snapshot()
    return { self.text, self.cursor, self.anchor }
end

function Editor:restore(from, to)
    if #from == 0 then
        return
    end
    to[#to + 1] = self:snapshot()
    local state = table.remove(from)
    self.text, self.cursor, self.anchor = state[1], state[2], state[3]
end

function Editor:replace(text, options)
    options = options or {}
    if options.readOnly then
        return
    end
    text = text:gsub('\r\n', '\n'):gsub('\r', '\n'):gsub('\t', '    ')
    if not options.multiline then
        text = text:gsub('\n', ' ')
    end
    local a, b = self:range()
    if options.maxLength and options.maxLength > 0 then
        local available =
            math.max(0, options.maxLength - utf8.len(self.text:sub(1, a) .. self.text:sub(b + 1)))
        local cut = utf8.offset(text, available + 1)
        if cut then
            text = text:sub(1, cut - 1)
        end
    end
    local value = self.text:sub(1, a) .. text .. self.text:sub(b + 1)
    if value == self.text then
        return
    end
    self.undo[#self.undo + 1] = self:snapshot()
    if #self.undo > 100 then
        table.remove(self.undo, 1)
    end
    self.redo = {}
    self.text, self.cursor, self.anchor = value, a + #text, a + #text
end

function Editor:move(at, extend)
    self.cursor = math.max(0, math.min(#self.text, at))
    if not extend then
        self.anchor = self.cursor
    end
end

function Editor:word(direction)
    local at = self.cursor
    local step = direction < 0 and previous or following
    local function category(pos)
        local first = direction < 0 and previous(self.text, pos) or pos
        local char = self.text:sub(first + 1, following(self.text, first))
        return char:match('%s') and 'space'
            or char:match('[%w_]') and 'word'
            or #char > 1 and 'word'
            or 'punctuation'
    end
    while at > 0 and at < #self.text and category(at) == 'space' do
        at = step(self.text, at)
    end
    local kind = category(at)
    repeat
        local nextAt = step(self.text, at)
        if nextAt == at then
            break
        end
        at = nextAt
    until at == 0 or at == #self.text or category(at) ~= kind
    return at
end

function Editor:key(key, mods, clipboard, options)
    mods, options = mods or {}, options or {}
    local ctrl, shift = mods.ctrl, mods.shift
    if ctrl and key == 'a' then
        self.anchor, self.cursor = 0, #self.text
    elseif ctrl and (key == 'c' or key == 'x') then
        if self.cursor ~= self.anchor then
            clipboard.set(self:selected())
            if key == 'x' then
                self:replace('', options)
            end
        end
    elseif ctrl and key == 'v' then
        self:replace(clipboard.get() or '', options)
    elseif ctrl and (key == 'z' or key == 'y') then
        if not options.readOnly then
            if key == 'y' or shift then
                self:restore(self.redo, self.undo)
            else
                self:restore(self.undo, self.redo)
            end
        end
    elseif key == 'left' or key == 'right' then
        local a, b = self:range()
        local at
        if not shift and a ~= b then
            at = key == 'left' and a or b
        elseif ctrl then
            at = self:word(key == 'left' and -1 or 1)
        else
            at = (key == 'left' and previous or following)(self.text, self.cursor)
        end
        self:move(at, shift)
    elseif key == 'home' or key == 'end' then
        local at = key == 'home' and 0 or #self.text
        if options.multiline and not ctrl then
            local before = self.text:sub(1, self.cursor)
            at = key == 'home' and (before:match('.*\n()') or 1) - 1
                or (self.text:find('\n', self.cursor + 1, true) or #self.text + 1) - 1
        end
        self:move(at, shift)
    elseif key == 'up' or key == 'down' then
        local before = self.text:sub(1, self.cursor)
        local start = (before:match('.*\n()') or 1) - 1
        local column = utf8.len(self.text:sub(start + 1, self.cursor))
        local target
        if key == 'up' then
            target = start > 0 and ((self.text:sub(1, start - 1):match('.*\n()') or 1) - 1) or 0
        else
            target = self.text:find('\n', self.cursor + 1, true) or #self.text
        end
        local finish = (self.text:find('\n', target + 1, true) or #self.text + 1) - 1
        local line = self.text:sub(target + 1, finish)
        self:move(
            target + (utf8.offset(line, math.min(column, utf8.len(line)) + 1) or #line + 1) - 1,
            shift
        )
    elseif key == 'backspace' or key == 'delete' then
        if self.cursor == self.anchor then
            self.anchor = ctrl and self:word(key == 'backspace' and -1 or 1)
                or (key == 'backspace' and previous or following)(self.text, self.cursor)
        end
        self:replace('', options)
    else
        return false
    end
    return true
end

return Editor

-- GLSL tokenizer used by the shader composer.
--
-- Tokens keep their exact text (including whitespace and comments), so a token list can be
-- joined back into source. Only identifiers are ever rewritten, and never inside comments or
-- preprocessor lines.
local Tokens = {}

local punctuation = {
    '<<=', '>>=', '++', '--', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<', '>>', '<=',
    '>=', '==', '!=', '&&', '||', '^^',
}

-- Returns an array of { kind, text, line } where kind is 'id', 'num', 'op', 'space', 'comment'
-- or 'directive' (a whole preprocessor line, continuations included).
function Tokens.scan(source)
    local list, count, position, line = {}, 0, 1, 1
    local length = #source
    local function push(kind, text)
        count = count + 1
        list[count] = { kind = kind, text = text, line = line }
        local _, newlines = text:gsub('\n', '')
        line = line + newlines
    end
    local lineStart = true
    while position <= length do
        local char = source:sub(position, position)
        local rest2 = source:sub(position, position + 1)
        if char == '\n' then
            push('space', '\n')
            position, lineStart = position + 1, true
        elseif char:match('%s') then
            local text = source:match('^[ \t\r\f\v]+', position)
            push('space', text)
            position = position + #text
        elseif rest2 == '//' then
            local text = source:match('^//[^\n]*', position)
            push('comment', text)
            position = position + #text
        elseif rest2 == '/*' then
            local finish = source:find('*/', position + 2, true)
            local text = source:sub(position, finish and finish + 1 or length)
            push('comment', text)
            position = position + #text
        elseif char == '#' and lineStart then
            local finish = position
            while true do
                local newline = source:find('\n', finish, true) or length + 1
                local before = source:sub(newline - 1, newline - 1)
                finish = newline
                if before ~= '\\' or newline > length then
                    break
                end
                finish = newline + 1
            end
            local text = source:sub(position, finish - 1)
            push('directive', text)
            position = position + #text
        elseif char:match('[%a_]') then
            local text = source:match('^[%w_]+', position)
            push('id', text)
            position, lineStart = position + #text, false
        elseif char:match('%d') or (char == '.' and source:sub(position + 1, position + 1):match('%d')) then
            local text = source:match('^0[xX]%x+[uU]?', position)
                or source:match('^[%d%.]+[eE][%+%-]?%d+[fF]?', position)
                or source:match('^[%d%.]+[fFuU]?', position)
            push('num', text)
            position, lineStart = position + #text, false
        else
            local text = char
            for _, candidate in ipairs(punctuation) do
                if source:sub(position, position + #candidate - 1) == candidate then
                    text = candidate
                    break
                end
            end
            push('op', text)
            position, lineStart = position + #text, false
        end
    end
    return list
end

function Tokens.join(list, first, last)
    local parts = {}
    for i = first or 1, last or #list do
        parts[#parts + 1] = list[i].text
    end
    return table.concat(parts)
end

-- True for tokens that carry meaning (not whitespace or comments).
function Tokens.significant(token)
    return token.kind ~= 'space' and token.kind ~= 'comment'
end

-- Index of the token that closes the bracket opened at `index`, or nil.
function Tokens.matching(list, index)
    local open = list[index].text
    local close = ({ ['('] = ')', ['{'] = '}', ['['] = ']' })[open]
    local depth = 0
    for i = index, #list do
        local token = list[i]
        if token.kind == 'op' then
            if token.text == open then
                depth = depth + 1
            elseif token.text == close then
                depth = depth - 1
                if depth == 0 then
                    return i
                end
            end
        end
    end
end

return Tokens

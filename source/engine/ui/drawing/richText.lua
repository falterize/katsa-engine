local pairs = require('../../math.array').pairs
-- Deliberately bounded markup subset; never evaluates code or external fonts.
local Rich = {}

local function decode(text)
    return (
        text:gsub('&lt;', '<')
            :gsub('&gt;', '>')
            :gsub('&quot;', '"')
            :gsub('&apos;', "'")
            :gsub('&amp;', '&')
    )
end

function Rich.parse(text, enabled)
    if not enabled then
        return { { text = text } }
    end
    assert(#text <= 65536, 'RichText exceeds the 64 KiB label limit')
    local result, stack = {}, { {} }

    local function append(value)
        if value == '' then
            return
        end
        local run = { text = decode(value) }
        for k, v in pairs(stack[#stack]) do
            run[k] = v
        end
        result[#result + 1] = run
    end
    local position = 1
    while position <= #text do
        local first, last, tag = text:find('<([^>]+)>', position)
        if not first then
            append(text:sub(position))
            break
        end
        append(text:sub(position, first - 1))
        local name = tag:match('^/?([%a]+)')
        if tag == 'br' or tag == 'br/' or tag == 'br /' then
            append('\n')
        elseif name == 'b' or name == 'i' or name == 'u' or name == 's' or name == 'font' then
            if tag:sub(1, 1) == '/' then
                assert(
                    #stack > 1 and stack[#stack].tag == name,
                    'RichText closing tag mismatch: ' .. tag
                )
                table.remove(stack)
            else
                assert(#stack < 33, 'RichText nesting exceeds 32 levels')
                local state = {}
                for k, v in pairs(stack[#stack]) do
                    state[k] = v
                end
                state.tag = name
                if name == 'font' then
                    local hex = tag:match('color%s*=%s*["\']#(%x+)["\']')
                    if hex then
                        assert(#hex == 6, 'RichText color must use #RRGGBB')
                        state.color = {
                            tonumber(hex:sub(1, 2), 16) / 255,
                            tonumber(hex:sub(3, 4), 16) / 255,
                            tonumber(hex:sub(5, 6), 16) / 255,
                        }
                    end
                    local size = tag:match('size%s*=%s*["\'](%d+)["\']')
                    if size then
                        size = tonumber(size)
                        assert(size >= 1 and size <= 200, 'RichText font size must be 1..200')
                        state.size = size
                    end
                else
                    state[name] = true
                end
                stack[#stack + 1] = state
            end
        else
            append(text:sub(first, last))
        end
        position = last + 1
    end
    assert(#stack == 1, 'RichText contains unclosed tags')
    return result
end

return Rich

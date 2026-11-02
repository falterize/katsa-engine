local unpack = require('../../math.array').unpack
local ipairs = require('../../math.array').ipairs
local Style = require('./popupStyle')
local palette, copy = Style.palette, Style.copy
local PopupColor = {}

function PopupColor.install(Popup)
    function Popup:setRGB(rgb)
        local maximum = self.field.colorMaximum
        for i = 1, 3 do
            local ok, err = require('../inspectors.properties').set(
                self.workspace.scene,
                self.target,
                self.field,
                tostring(rgb[i] * maximum),
                i
            )
            if not ok then
                self.message.text = err
                return false
            end
        end
        self.rgb = rgb
        self.preview.backgroundColor = { unpack(rgb) }
        self.hex.text = string.format(
            '#%02X%02X%02X',
            math.floor(rgb[1] * 255 + 0.5),
            math.floor(rgb[2] * 255 + 0.5),
            math.floor(rgb[3] * 255 + 0.5)
        )
        for i = 1, 3 do
            self.channels[i].value = rgb[i]
            self.numbers[i].text = tostring(math.floor(rgb[i] * 255 + 0.5))
        end
        self.ui:invalidate()
        return true
    end

    function Popup:colorEditor()
        self.color = true
        self.rgb = {}
        self.channels = {}
        self.numbers = {}
        for i = 1, 3 do
            self.rgb[i] = self.original[i] / self.field.colorMaximum
        end
        self.preview = self.ui:container(
            { position = { 0, 6, 0, 0 }, size = { 1, -12, 0, 32 }, backgroundColor = self.rgb },
            self.body
        )
        for i, c in ipairs(palette) do
            self.ui:button({
                position = { (i - 1) % 6 / 6, 4, 0, 40 + math.floor((i - 1) / 6) * 34 },
                size = { 1 / 6, -8, 0, 30 },
                text = '',
                backgroundColor = c,
                onPress = function()
                    self:setRGB({ unpack(c) })
                end,
            }, self.body)
        end
        for i, label in ipairs({ 'R', 'G', 'B' }) do
            local index = i
            local y = 150 + (i - 1) * 46
            self.ui:text({
                position = { 0, 4, 0, y },
                size = { 0, 20, 0, 38 },
                text = label,
                fontSize = 13,
                padding = 0,
                align = 'left',
            }, self.body)
            self.channels[i] = self.ui:slider({
                position = { 0.08, 4, 0, y },
                size = { 0.6, -12, 0, 38 },
                value = self.rgb[i],
                onChange = function(v)
                    local rgb = { unpack(self.rgb) }
                    rgb[index] = v
                    self:setRGB(rgb)
                end,
            }, self.body)
            local n = self:input(
                '',
                tostring(math.floor(self.rgb[i] * 255 + 0.5)),
                y,
                function(text)
                    local v = tonumber(text)
                    if not v or v ~= v or v < 0 or v > 255 then
                        return false, 'RGB must be 0..255'
                    end
                    local rgb = { unpack(self.rgb) }
                    rgb[index] = v / 255
                    return self:setRGB(rgb)
                end
            )
            -- Numeric controls occupy the right half beside the slider.
            n.position = { 0.72, 0, 0, y }
            n.size = { 0.28, -6, 0, 38 }
            self.numbers[i] = n
        end
        self.hex = self:input('HEX', '#FFFFFF', 292, function(text)
            local hex = text:match('^#?(%x%x%x%x%x%x)$')
            if not hex then
                return false, 'Use #RRGGBB'
            end
            local rgb = {}
            for i = 1, 3 do
                rgb[i] = tonumber(hex:sub(i * 2 - 1, i * 2), 16) / 255
            end
            return self:setRGB(rgb)
        end)
        self.body.length = 336
        self:setRGB(self.rgb)
    end
end

return PopupColor

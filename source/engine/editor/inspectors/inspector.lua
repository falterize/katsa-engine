local Array = require('../../math.array')
local ipairs = require('../../math.array').ipairs
local pairs = require('../../math.array').pairs
local Properties = require('./properties')
local buttonColor = require('../../ui.theme').button

local function clear(node)
    while #node.children > 0 do
        node.children[#node.children]:destroy()
    end
end

local function category(key)
    if ({ parent = true, name = true, visible = true, enabled = true, zIndex = true })[key] then
        return 'Identity'
    end
    if
        ({
            spatialPosition = true,
            position = true,
            size = true,
            rotation = true,
            scale = true,
            anchorPoint = true,
            relativeTo = true,
            sizeRelativeTo = true,
            positionRelativeTo = true,
            face = true,
            canvasSize = true,
            screenOffset = true,
        })[key]
    then
        return 'Layout / Transform'
    end
    if
        key:lower():find('color')
        or key:find('Transparency')
        or ({
            text = true,
            fontSize = true,
            textScaled = true,
            richText = true,
            image = true,
            mode = true,
            tileSize = true,
            imageOffset = true,
            imageRotation = true,
        })[key]
    then
        return 'Appearance'
    end
    if
        key:lower():find('shadow')
        or ({
            resolution = true,
            filterSamples = true,
            updateHz = true,
            distance = true,
            fadeDistance = true,
            maxUpdateFaces = true,
            bias = true,
            normalBias = true,
        })[key]
    then
        return 'Shadows'
    end
    return 'Settings'
end
local Inspector = {}

-- The nearest ancestor with Interactable off, if any. Such an ancestor disables input for the
-- whole branch below it, so the node's own Interactable setting has no effect.
function Inspector.interactableBlocker(node)
    local ancestor = node and node.parent
    while ancestor do
        if ancestor.interactable == false then
            return ancestor
        end
        ancestor = ancestor.parent
    end
end

function Inspector.install(Workspace)
    function Workspace:select(node, preserveScroll)
        local oldScroll = preserveScroll and self.properties.scrollY or 0
        self.parentPathText, self.parentPathValue = nil, nil
        if self.popup then
            self.popup:close(false)
        end
        self:cancelEdit()
        self.selected = node
        clear(self.properties)
        self.propertyButtons = {}
        self.fields = Properties.list(node._editorTarget or node)
        self.schemaSignature =
            require('./schema').signature(node._editorTarget or node)
        local groups = {}
        for _, field in ipairs(self.fields) do
            local name = category(field.key)
            groups[name] = groups[name] or {}
            groups[name][#groups[name] + 1] = field
        end
        local y = 0
        for _, name in ipairs({
            'Identity',
            'Layout / Transform',
            'Appearance',
            'Shadows',
            'Settings',
        }) do
            if groups[name] then
                self.ui:button({
                    position = { 0, 6, 0, y },
                    size = { 1, -12, 0, 30 },
                    text = (self.categoryCollapsed[name] and '+ ' or '- ') .. name,
                    fontSize = 15,
                    align = 'left',
                    backgroundColor = buttonColor,
                    onPress = function()
                        self.categoryCollapsed[name] = not self.categoryCollapsed[name]
                        self:select(node)
                    end,
                }, self.properties)
                y = y + 34
                if not self.categoryCollapsed[name] then
                    for _, field in ipairs(groups[name]) do
                        if field.key == 'parent' then
                            self.parentPathValue = field.value
                            self.parentPathText = self.ui:text({
                                position = { 0, 8, 0, y },
                                size = { 1, -16, 0, 44 },
                                text = 'parent: ' .. field.value,
                                fontSize = 13,
                                textScaled = true,
                                maxTextSize = 13,
                                align = 'left',
                            }, self.properties)
                            y = y + 48
                        else
                            local compact = field.kind ~= 'vector' or field.colorMaximum ~= nil
                            -- Interactable is cascading: an ancestor that has it off blocks this node
                            -- (and everything inside it), whatever its own value says.
                            local blocker = field.key == 'interactable'
                                and Inspector.interactableBlocker(node)
                            local blockedHint = blocker
                                and ('Blocked: ancestor "%s" has Interactable off, so this node and its '
                                    .. 'descendants take no input.'):format(tostring(blocker.name))
                            self.ui:text({
                                position = { 0, 8, 0, y },
                                size = compact and { 0.42, -12, 0, 40 } or { 1, -16, 0, 24 },
                                text = blocker and (field.key .. '  !') or field.key,
                                textColor = blocker and { 1, 0.72, 0.2 } or nil,
                                onPress = function()
                                    if blockedHint then
                                        self.status.text = blockedHint
                                    end
                                    self:showHint(field)
                                end,
                                onEnter = function()
                                    if blockedHint then
                                        self.status.text = blockedHint
                                    elseif field.hint then
                                        self.status.text = field.hint
                                    end
                                end,
                                fontSize = 13,
                                textScaled = true,
                                maxTextSize = 13,
                                align = 'left',
                            }, self.properties)
                            if not compact then
                                y = y + 26
                            end
                            local count = field.colorMaximum and 1
                                or field.kind == 'vector' and #field.value
                                or 1
                            local labels = field.labels
                                or count == 4 and { 'Scale X', 'Offset X', 'Scale Y', 'Offset Y' }
                                or count == 3 and { 'X', 'Y', 'Z' }
                                or { 'X', 'Y' }
                            if count > 1 then
                                for c = 1, count do
                                    self.ui:text({
                                        position = { (c - 1) / count, 4, 0, y },
                                        size = { 1 / count, -8, 0, 18 },
                                        text = labels[c],
                                        fontSize = 10,
                                        textScaled = true,
                                        maxTextSize = 10,
                                    }, self.properties)
                                end
                                y = y + 18
                            end
                            for c = 1, count do
                                local component = field.kind == 'vector'
                                        and not field.colorMaximum
                                        and c
                                    or nil
                                local button = self.ui:button({
                                    position = compact and { 0.42, 0, 0, y }
                                        or {
                                            (c - 1) / count,
                                            4,
                                            0,
                                            y,
                                        },
                                    size = compact and { 0.58, -8, 0, 40 }
                                        or { 1 / count, -8, 0, 40 },
                                    fontSize = 13,
                                    textScaled = true,
                                    maxTextSize = 13,
                                    backgroundColor = buttonColor,
                                    onPress = function()
                                        if field.readOnly then
                                            self.status.text = field.reason or 'Read-only property'
                                            return
                                        end
                                        if
                                            field.options
                                            or field.colorMaximum
                                            or field.kind == 'node'
                                            or field.kind == 'gradient'
                                            or field.kind == 'sequence'
                                            or field.kind == 'bindings'
                                        then
                                            self:openPopup(field)
                                            return
                                        end
                                        if field.kind == 'boolean' then
                                            local ok, err = Properties.set(
                                                self.scene,
                                                node._editorTarget or node,
                                                field,
                                                not self:value(field)
                                            )
                                            self.status.text = ok and (field.key .. ' updated')
                                                or err
                                        elseif field.kind == 'vector' then
                                            self:openPopup(field)
                                        else
                                            self:beginEdit(field, component)
                                        end
                                    end,
                                }, self.properties)
                                self.propertyButtons[#self.propertyButtons + 1] =
                                    { button = button, field = field, component = component }
                            end
                            y = y + 48
                        end
                    end
                end
            end
        end
        self.properties.length = y
        self.properties.scrollY = oldScroll
        self.ui:scrollBy(self.properties, 0)
        self.status.text = (node.name or node.className) .. ' / ' .. (node.className or 'Settings')
        self:updateValues()
    end

    function Workspace:value(field, component)
        local target = self.selected._editorTarget or self.selected
        local getter =
            require('./schema').descriptor(target, field.key).get
        if getter then
            return getter(target)
        end
        local value = field.key == 'parent' and Properties.parentPath(target)
            or (field.container or target)[field.storageKey or field.key]
        if value == nil then
            value = field.value
        end
        return component and value[component] or value
    end

    function Workspace:updateValues()
        for _, item in ipairs(self.propertyButtons) do
            local v = self:value(item.field, item.component)
            if item.field.colorMaximum and Array.is(v) then
                local maximum = item.field.colorMaximum
                item.button.text = string.format(
                    '#%02X%02X%02X',
                    math.floor(v[1] / maximum * 255 + 0.5),
                    math.floor(v[2] / maximum * 255 + 0.5),
                    math.floor(v[3] / maximum * 255 + 0.5)
                )
                item.button.backgroundColor = { v[1] / maximum, v[2] / maximum, v[3] / maximum }
                item.button.textColor = (v[1] + v[2] + v[3]) / maximum > 1.6 and { 0, 0, 0 }
                    or { 1, 1, 1 }
            elseif item.field.kind == 'node' then
                if type(v) == 'string' then
                    item.button.text = v .. ' [model]'
                else
                    item.button.text = v and (v.name .. ' [' .. v.className .. '] ▾')
                        or 'None ▾'
                end
            elseif item.field.kind == 'bindings' then
                if self.selected.isA and self.selected:isA('Ramp') then
                    local seen, count = {}, 0
                    for key in pairs(self.selected.goals) do
                        seen[key] = true
                        count = count + 1
                    end
                    for key in pairs(self.selected.bindings) do
                        if not seen[key] then
                            count = count + 1
                        end
                    end
                    item.button.text = count .. ' goals / edit ▾'
                else
                    item.button.text = 'Edit entries ▾'
                end
            elseif item.field.kind == 'sequence' then
                item.button.text = #v .. ' points ▾'
            else
                item.button.text = (type(v) == 'number' and string.format('%.5g', v) or tostring(v))
                    .. (
                        item.field.options and ' ▾'
                        or item.field.readOnly and ' [read only]'
                        or ''
                    )
            end
        end
    end

    function Workspace:showHint(field)
        if not field.hint and not field.reason then
            self.status.text = field.key
            return
        end
        if self.popup then
            self.popup:close(false)
        end
        self:cancelEdit()
        self.popup = require('../panels.popup').new(self, field)
        self.popup:hintEditor(field.hint or field.reason)
    end

    function Workspace:openPopup(field)
        if self.popup then
            self.popup:close(false)
        end
        self:cancelEdit()
        self.popup = require('../panels.popup').new(self, field)
        if field.kind == 'node' then
            self.popup:nodeEditor()
        elseif field.kind == 'sequence' then
            require('../curves.sequenceEditor').open(self.popup)
        elseif field.kind == 'bindings' then
            require('../curves.sequenceEditor').bindings(self.popup)
        elseif field.options then
            self.popup:enum()
        elseif field.colorMaximum then
            self.popup:colorEditor()
        else
            self.popup:vectorEditor()
        end
    end
end

return Inspector

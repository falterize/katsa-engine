local Screen = {}

function Screen.create(traceback, api)
    api = api or katsa
    if api.filesystem then
        pcall(
            require('./crashHistory').write,
            api.filesystem,
            traceback,
            api.log and api.log.tail(50)
        )
    end
    if api.mouse then
        pcall(api.mouse.setRelativeMode, false)
        pcall(api.mouse.setGrabbed, false)
        pcall(api.mouse.setVisible, true)
    end
    if api.keyboard then
        pcall(api.keyboard.setTextInput, false)
        pcall(api.keyboard.setKeyRepeat, false)
    end
    if api.audio then
        pcall(api.audio.stop)
    end
    -- Drop queued gameplay events, including Escape/quit events from the failing
    -- frame. Only a new explicit window-close request ends the error screen.
    if api.event and api.event.clear then
        api.event.clear()
    end
    -- The font has no glyph for tabs (they print as "?" at the start of traceback lines), and
    -- carriage returns or control bytes do the same. Show them as spaces.
    local shown = tostring(traceback)
        :gsub('\r\n?', '\n')
        :gsub('\t', '    ')
        :gsub('[%z\1-\8\11\12\14-\31]', ' ')
    local g, scroll, font = api.graphics, 0, nil
    if g and g.isActive() then
        g.reset()
        font = g.newFont(16)
    end
    return function()
        if api.event then
            api.event.pump()
            for event, key, delta in api.event.poll() do
                if event == 'quit' then
                    return 1
                end
                if event == 'wheelmoved' then
                    scroll = math.max(0, scroll - (delta or 0) * 48)
                end
                if
                    event == 'keypressed'
                    and key == 'c'
                    and api.keyboard
                    and api.keyboard.isDown('lctrl', 'rctrl', 'lgui', 'rgui')
                    and api.system
                then
                    api.system.setClipboardText(traceback)
                end
            end
        end
        if g and g.isActive() then
            g.setCanvas()
            g.setShader()
            g.origin()
            g.setScissor()
            g.setFont(font)
            g.clear(0.07, 0.025, 0.035)
            g.setColor(1, 0.8, 0.8)
            g.printf(
                'Katsa stopped after an error. Close the window to exit.\n'
                    .. 'Ctrl+C: copy | Wheel: scroll | Saved: crashes/crash-01.log (last 10)\n\n'
                    .. shown,
                24,
                24 - scroll,
                math.max(1, g.getWidth() - 48)
            )
            g.present()
        end
        if api.timer then
            api.timer.sleep(0.05)
        end
    end
end

return Screen

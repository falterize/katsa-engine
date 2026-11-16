-- Picks the test flags that cover the files you changed and optionally runs them.
--   luajit tools/dev/testChanged.lua                  list flags for uncommitted changes
--   luajit tools/dev/testChanged.lua --run            run them one by one (runTests.sh)
--   luajit tools/dev/testChanged.lua --since v108.4   compare with a branch, tag or commit
--   luajit tools/dev/testChanged.lua --timeout 600    seconds per suite (default 900)
-- The map is tools/dev/testMap.lua. This is a shortcut while working; run the suites you rely on
-- (`--test-v106.8`, `--test`) in full before committing a large change.
package.path = 'tools/dev/?.lua;' .. package.path
local Map = require('testMap')

local function lines(command)
    local result = {}
    local pipe = assert(io.popen(command .. ' 2>/dev/null'))
    for line in pipe:lines() do
        result[#result + 1] = line
    end
    pipe:close()
    return result
end

local function startsWith(text, prefix)
    return text:sub(1, #prefix) == prefix
end

local function startsWithAny(text, list)
    for _, prefix in ipairs(list) do
        if startsWith(text, prefix) then
            return true
        end
    end
    return false
end

local options = { since = 'HEAD', timeout = 900 }
do
    local index = 1
    while index <= #arg do
        local value = arg[index]
        if value == '--run' then
            options.run = true
        elseif value == '--since' then
            index = index + 1
            options.since = arg[index]
        elseif value == '--timeout' then
            index = index + 1
            options.timeout = tonumber(arg[index])
        else
            error('Unknown option: ' .. value)
        end
        index = index + 1
    end
end

local registry = io.open('validation/tests/registry.lua'):read('*a')
local function known(flag)
    return registry:find("['" .. flag .. "']", 1, true) ~= nil
end

if #lines('git rev-parse --verify --quiet ' .. options.since .. '^{commit}') == 0 then
    error('Unknown git reference: ' .. tostring(options.since), 0)
end
local files = lines('git diff --name-only ' .. options.since)
for _, file in ipairs(lines('git ls-files --others --exclude-standard')) do
    files[#files + 1] = file
end

local flags, order = {}, {}
local function add(flag)
    if not flags[flag] then
        flags[flag] = true
        order[#order + 1] = flag
    end
end

for _, file in ipairs(files) do
    local major, minor = file:match('^validation/tests/versions/v(%d+)_(%d+)/')
    if startsWithAny(file, Map.ignore) or file:match('%.md$') then
        -- Documentation and packaging need no test run.
    elseif major then
        add('--test-v' .. major .. '.' .. minor)
    else
        local matched = false
        for _, rule in ipairs(Map.rules) do
            if startsWith(file, rule.prefix) then
                matched = true
                for _, flag in ipairs(rule.flags) do
                    add(flag)
                end
            end
        end
        if not matched and startsWithAny(file, Map.code) then
            for _, flag in ipairs(Map.fallback) do
                add(flag)
            end
        end
    end
end

if #order == 0 then
    print('No test suite is affected by ' .. #files .. ' changed file(s).')
    return
end
for _, flag in ipairs(order) do
    if not known(flag) then
        io.stderr:write('warning: ' .. flag .. ' is not in validation/tests/registry.lua\n')
    end
end
print(#files .. ' changed file(s) -> ' .. table.concat(order, ' '))
if not options.run then
    return
end

local failed = false
for _, flag in ipairs(order) do
    local started = os.time()
    local output = lines(string.format('tools/dev/runTests.sh %s %d', flag, options.timeout))
    local summary = output[1] or '(no output)'
    print(string.format('%-18s %s  [%ds]', flag, summary, os.time() - started))
    for index = 2, #output do
        if output[index]:match('^FAIL') then
            print('    ' .. output[index])
        end
    end
    if not summary:match('failed: 0 ') then
        failed = true
    end
end
os.exit(failed and 1 or 0)

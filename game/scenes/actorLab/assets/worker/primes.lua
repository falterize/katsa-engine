-- Runs on a worker thread, in its own Lua state: no scene, no graphics, only plain data in and
-- out. Every request carries a range; the answer is how many primes it holds.
local function countPrimes(from, to)
    local count = 0
    for n = math.max(2, from), to do
        local prime = true
        for d = 2, math.floor(math.sqrt(n)) do
            if n % d == 0 then
                prime = false
                break
            end
        end
        if prime then
            count = count + 1
        end
    end
    return count
end

-- `Actor.on(topic, fn)`: a value returned here answers `actor:request(topic, data, callback)`.
Actor.on('count', function(range)
    return countPrimes(range.from, range.to)
end)

-- Fire-and-forget messages work too: `actor:send('ping', data)`; the worker may talk back with
-- `Actor.send(topic, data)`, which arrives at `actor:on(topic, handler)`.
Actor.on('ping', function(data)
    Actor.send('pong', { worker = Actor.args.name, echo = data.value })
end)

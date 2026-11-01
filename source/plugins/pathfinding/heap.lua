-- Binary min-heap keyed by a numeric priority. Stable enough for A*: ties pop in insertion order.
local Heap = {}
Heap.__index = Heap

function Heap.new()
    return setmetatable({ items = {}, priorities = {}, orders = {}, size = 0, counter = 0 }, Heap)
end

local function less(self, a, b)
    local pa, pb = self.priorities[a], self.priorities[b]
    return pa < pb or pa == pb and self.orders[a] < self.orders[b]
end

local function swap(self, a, b)
    local items, priorities, orders = self.items, self.priorities, self.orders
    items[a], items[b] = items[b], items[a]
    priorities[a], priorities[b] = priorities[b], priorities[a]
    orders[a], orders[b] = orders[b], orders[a]
end

function Heap:push(item, priority)
    self.size = self.size + 1
    self.counter = self.counter + 1
    local index = self.size
    self.items[index], self.priorities[index], self.orders[index] = item, priority, self.counter
    while index > 1 do
        local parent = math.floor(index / 2)
        if not less(self, index, parent) then
            break
        end
        swap(self, index, parent)
        index = parent
    end
end

function Heap:pop()
    if self.size == 0 then
        return nil
    end
    local top = self.items[1]
    local last = self.size
    swap(self, 1, last)
    self.items[last], self.priorities[last], self.orders[last] = nil, nil, nil
    self.size = last - 1
    local index = 1
    while true do
        local left, right, smallest = index * 2, index * 2 + 1, index
        if left <= self.size and less(self, left, smallest) then
            smallest = left
        end
        if right <= self.size and less(self, right, smallest) then
            smallest = right
        end
        if smallest == index then
            break
        end
        swap(self, index, smallest)
        index = smallest
    end
    return top
end

function Heap:isEmpty()
    return self.size == 0
end

return Heap

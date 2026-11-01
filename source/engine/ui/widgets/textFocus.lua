-- One keyboard focus per application; destroyed nodes explicitly release it.
local Focus = { current = nil }
return Focus

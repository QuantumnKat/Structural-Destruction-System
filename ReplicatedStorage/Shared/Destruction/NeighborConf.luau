--!strict

local NeighborConf = {}

local DEFAULT = {
	Gap      = 0.05,
	CellSize = 16,
}

local current = {
	Gap      = DEFAULT.Gap,
	CellSize = DEFAULT.CellSize,
}

function NeighborConf.Get(): { Gap: number, CellSize: number }
	return current
end

-- Override runtime. VD: NeighborConf.Set({ Gap = 0.1, CellSize = 12 })
function NeighborConf.Set(overrides: { Gap: number?, CellSize: number? }?)
	if overrides then
		if overrides.Gap      ~= nil then current.Gap      = overrides.Gap      end
		if overrides.CellSize ~= nil then current.CellSize = overrides.CellSize end
	end
end

function NeighborConf.Reset()
	current.Gap      = DEFAULT.Gap
	current.CellSize = DEFAULT.CellSize
end

return NeighborConf

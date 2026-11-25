--!strict
--!native

local State: any = {
	graph = nil,
	physicalPartMap = {} :: { [number]: BasePart },
	ActiveParts = {} :: { BasePart },
	replication = nil,
	mapFolder = nil,
	_dirty = true,
	_lastRefresh = 0,
}

local ctx: any = nil

function State.Init(c: any)
	ctx = c
	State.replication = c.Mods.ServerReplication.new()
end

function State.IsReady(): boolean
	return State.graph ~= nil
end

function State.MarkDirty()
	State._dirty = true
end

function State.Reset()
	local map: { [number]: BasePart } = State.physicalPartMap
	for _, p in pairs(map) do
		if p and p.Parent then p:Destroy() end
	end
	for k in pairs(map) do map[k] = nil end

	local active: { BasePart } = State.ActiveParts
	for i = #active, 1, -1 do
		local p = active[i]
		if p and p.Parent then p:Destroy() end
		active[i] = nil
	end

	State.graph = nil
	State.mapFolder = nil
	State._dirty = true
end

function State.GetPartMap(force: boolean?): { [number]: BasePart }
	local map: { [number]: BasePart } = State.physicalPartMap
	local folder = State.mapFolder
	if not folder or not ctx then return map end

	local now = os.clock()
	if force or State._dirty or now - State._lastRefresh >= ctx.Config.PartMap.RefreshInterval then
		local built = ctx.Mods.PartIndexMap.Build(folder)
		if built ~= map then
			for k in pairs(map) do map[k] = nil end
			for k, v in pairs(built) do map[k] = v end
		end
		State._dirty = false
		State._lastRefresh = now
	end
	return map
end

function State.CountNodes(): number
	local n = 0
	local g = State.graph
	if g then
		for _ in pairs(g.Nodes) do n += 1 end
	end
	return n
end

return State

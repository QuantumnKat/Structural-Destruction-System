--!strict
--!native

local MapService: any = {}

local ctx: any = nil

function MapService.Init(c: any)
	ctx = c
end

function MapService.FindMapFolder(): Instance?
	local ws = ctx.Services.Workspace
	local cam = ws:FindFirstChild("Camera")
	if cam then
		local map = cam:FindFirstChild("Map")
		if map then return map end
	end
	return ws:FindFirstChild("Map")
end

local function count(t: any): number
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

function MapService.NodesToPartData(nodes: any, parts: any): { [number]: any }
	local out: { [number]: any } = {}
	for idx, node in pairs(nodes) do
		local src = parts[idx]
		out[idx] = {
			Name                = node.Name,
			CFrame              = src and src.CFrame or CFrame.new(node.Position),
			Size                = node.Size,
			Color               = src and src.Color or Color3.new(0.7, 0.7, 0.7),
			Material            = src and src.Material.Value or Enum.Material.Concrete.Value,
			PartIndex           = idx,
			Mass                = node.Mass,
			HP                  = node.HP,
			TensileStrength     = node.TensileStrength,
			BendingForce        = node.BendingForce,
			CompressionStrength = node.CompressionStrength,
			IsAnchor            = node.IsAnchor,
			IsDestructible      = true,
			OnDisconnect        = src and src:GetAttribute("OnDisconnect") or "Auto",
			BreakRadius         = src and src:GetAttribute("BreakRadius") or 4,
			ShatterAirPercent   = src and src:GetAttribute("ShatterAirPercent") or 0.5,
			MaxDebrisPerPart    = src and src:GetAttribute("MaxDebrisPerPart") or 64,
			ForceTransmission   = node.ForceTransmission,
			UnweldPercentage    = node.UnweldPercentage,
		}
	end
	return out
end

local function registerCollideHandler()
	local State, Mods, Remote = ctx.State, ctx.Mods, ctx.Remote
	local mode: string = ctx.Config.Collide.Mode

	Mods.ObjectManager.RegisterEventHandler("CollideEvent", function(buf: buffer?)
		if not buf or not State.graph then return end

		if mode == "Shape" then
			Mods.Handler.HandleCollisionImpacts(buf)

		elseif mode == "Legacy" then
			local ids, force = Mods.CollideCheck.decodeCollidePayload(buf)
			local map = State.GetPartMap()
			for _, partId in ipairs(ids) do
				for idx, p in pairs(map) do
					if p and p.Parent and p:GetAttribute("ObjectId") == partId then
						pcall(function()
							Mods.Handler.HandleHit(State.graph, nil, idx, force, Remote.Event, State.ActiveParts)
						end)
						State.MarkDirty()
						break
					end
				end
			end
		end
	end)
end

function MapService.Load(): boolean
	local State, Mods, Remote, Log = ctx.State, ctx.Mods, ctx.Remote, ctx.Log
	State.Reset()

	local mapFolder = MapService.FindMapFolder()
	if not mapFolder then
		Log.Warn("Map", "No Map folder found")
		return false
	end

	local nRaw = 0
	for _, d in ipairs(mapFolder:GetDescendants()) do
		if d:IsA("BasePart") then nRaw += 1 end
	end
	Log.Info("Map", "Map folder has %d BaseParts", nRaw)
	if nRaw == 0 then
		Log.Warn("Map", "Map folder empty — skipping graph build")
		return false
	end

	local payload = Mods.MapLoader.LoadMap(mapFolder)
	State.graph = Mods.StructureGraph.new(payload)
	State.mapFolder = mapFolder
	Log.Info("Map", "Graph: %d parts, %d welds", count(payload.Parts), count(payload.Welds or {}))

	local map: { [number]: BasePart } = State.physicalPartMap
	for _, part in ipairs(mapFolder:GetDescendants()) do
		if part:IsA("BasePart") then
			local idx = part:GetAttribute("PartIndex")
			if idx then map[idx] = part end
		end
	end

	Mods.ObjectManager.init()
	Mods.ObjectManager.RegisterActiveParts(State.ActiveParts)

	Mods.Handler.SetContext(State.graph, Remote.Event, State.ActiveParts)
	registerCollideHandler()

	State.MarkDirty()
	return true
end

local function serialize(): buffer?
	local State, Mods = ctx.State, ctx.Mods
	if not State.graph then return nil end
	local partData = MapService.NodesToPartData(State.graph.Nodes, State.GetPartMap(true))
	return Mods.MapSerializer.SerializeMap(partData)
end

function MapService.NotifyAll()
	local buf = serialize()
	if not buf then return end
	local players = ctx.Services.Players:GetPlayers()
	for _, player in ipairs(players) do
		ctx.Remote.Event:FireClient(player, "MAP_DATA", buf)
	end
	ctx.Log.Info("Map", "MAP_DATA -> %d clients (%.1f KB)", #players, buffer.len(buf) / 1024)
end

function MapService.SendTo(player: Player)
	local buf = serialize()
	if not buf then return end
	ctx.Remote.Event:FireClient(player, "MAP_DATA", buf)
	ctx.Log.Info("Map", "MAP_DATA -> %s (%.1f KB)", player.Name, buffer.len(buf) / 1024)
end

function MapService.Rebuild(): boolean
	ctx.Log.Info("Map", "Rebuilding graph...")
	local ok = MapService.Load()
	if ok then
		MapService.NotifyAll()
		ctx.Log.Info("Map", "Rebuild done")
	end
	return ok
end

return MapService

--!strict
--!native

local Requests: any = {}
local Validation = require(script.Parent.RequestValidation)

local ctx: any = nil
local buckets: { [number]: { tokens: number, t: number } } = {}

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function allow(player: Player): boolean
	local cfg = ctx.Config.Requests
	local now = os.clock()
	local b = buckets[player.UserId]
	if not b then
		b = { tokens = cfg.MaxPerSecond, t = now }
		buckets[player.UserId] = b
	end
	b.tokens = math.min(cfg.MaxPerSecond * 2, b.tokens + (now - b.t) * cfg.MaxPerSecond)
	b.t = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end

local function nearEnough(player: Player, pos: Vector3): boolean
	local cfg = ctx.Config.Requests
	if not cfg.RequireCharacter then return true end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return false end
	return (root.Position - pos).Magnitude <= cfg.MaxDistance
end

local function nodePosition(idx: number): Vector3?
	local g = ctx.State.graph
	local node = g and g.Nodes[idx]
	if not node or not node.IsActive then return nil end
	return node.Position
end

function Requests.Init(c: any)
	ctx = c
	local State, Remote, Log, Handler = c.State, c.Remote, c.Log, c.Mods.Handler
	local cfg = c.Config.Requests

	c.Services.Players.PlayerRemoving:Connect(function(p: Player)
		buckets[p.UserId] = nil
	end)

	Remote.Event.OnServerEvent:Connect(function(player: Player, action: string, data: any)
		if action == "DEBUG_PROBE_REPLY" then
			if c.Debug then c.Debug.Probe.OnReply(player, data) end
			return
		end

		if action ~= "HIT_REQUEST" and action ~= "BREAK_AT_POSITION" then return end
		if not allow(player) then return end
		if not Validation.validate(action, data) then return end
		if not State.graph then return end

		if action == "HIT_REQUEST" then
			local idx = data and data.idx
			local force = data and data.force
			if type(idx) ~= "number" or not finite(force) then return end

			if cfg.Validate then
				local pos = nodePosition(idx)
				if not pos or not nearEnough(player, pos) then
					Log.Print("Requests", "reject HIT_REQUEST idx=%s from %s", tostring(idx), player.Name)
					return
				end
				force = math.clamp(force, 0, cfg.MaxForce)
			end

			Log.Print("Hits", "HIT_REQUEST %s idx=%d force=%.0f", player.Name, idx, force)
			local ok, err = pcall(Handler.HandleHit, State.graph, nil, idx, force, Remote.Event, State.ActiveParts)
			if not ok then Log.Warn("Requests", "HandleHit error: %s", tostring(err)) end
			State.MarkDirty()

		elseif action == "BREAK_AT_POSITION" then
			local idx = data and data.idx
			local pos = data and data.pos
			local radius = data and data.radius or 4
			if type(idx) ~= "number" or typeof(pos) ~= "Vector3" or not finite(radius) then return end

			if cfg.Validate then
				local node = State.graph.Nodes[idx]
				if not nodePosition(idx) or not nearEnough(player, node.Position) or not nearEnough(player, pos)
					or not Validation.intersectsNode(pos, math.min(radius, cfg.MaxRadius), node) then
					Log.Print("Requests", "reject BREAK_AT_POSITION idx=%s from %s", tostring(idx), player.Name)
					return
				end
				radius = math.clamp(radius, 0.5, cfg.MaxRadius)
			end

			Log.Print("Hits", "BREAK_AT_POSITION %s idx=%d r=%.1f", player.Name, idx, radius)
			local ok, err = pcall(Handler.BreakAtPosition, State.graph, idx, pos, radius, nil, Remote.Event, State.ActiveParts)
			if not ok then Log.Warn("Requests", "BreakAtPosition error: %s", tostring(err)) end
			State.MarkDirty()
		end
	end)
end

return Requests
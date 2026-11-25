--!strict
--!native

local Debug: any = {}
Debug.Handlers = {} :: { [string]: (Player, ...any) -> any }

local ctx: any = nil

function Debug.Register(name: string, fn: (Player, ...any) -> any)
	Debug.Handlers[name] = fn
end

local function allowed(player: Player): boolean
	local cfg = ctx.Config.Debug
	if cfg.AllowInStudio and ctx.Services.RunService:IsStudio() then
		return true
	end
	for _, id in ipairs(cfg.AllowedUserIds) do
		if id == player.UserId then return true end
	end
	return false
end

local function count(t: any): number
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

function Debug.Init(c: any)
	ctx = c
	local Log = c.Log

	Debug.Remote = c.Remote.GetOrCreate(c.Services.ReplicatedStorage, "RemoteFunction", c.Config.Remote.Debug) :: RemoteFunction
	Debug.Draw = require(script.Draw) :: any
	Debug.Probe = require(script.DesyncProbe) :: any

	Debug.Draw.Init(c)
	Debug.Probe.Init(c)

	-- ── lệnh dựng sẵn ──
	Debug.Register("help", function()
		local names = {}
		for name in pairs(Debug.Handlers) do names[#names + 1] = name end
		table.sort(names)
		return names
	end)

	Debug.Register("flags", function(_, cat: any, on: any)
		if type(cat) == "string" and type(on) == "boolean" then
			Log.SetFlag(cat, on)
		end
		return Log.GetFlags()
	end)

	Debug.Register("logs", function(_, n: any)
		return Log.Tail(if type(n) == "number" then n else 50)
	end)

	Debug.Register("clear_draw", function()
		Debug.Draw.Clear()
		return "cleared"
	end)

	Debug.Register("stats", function()
		local M, S = c.Mods, c.State
		local sleeping, awake = 0, 0
		for _, p in ipairs(S.ActiveParts) do
			if p and p.Parent then
				if p:GetAttribute("IsSleeping") then sleeping += 1 else awake += 1 end
			end
		end
		local g = S.graph
		return {
			server = {
				ready = g ~= nil,
				nodes = S.CountNodes(),
				activeWelds = g and count(g.ActiveWelds) or 0,
				activeParts = #S.ActiveParts, sleeping = sleeping, awake = awake,
				players = #c.Services.Players:GetPlayers(),
				memoryKB = math.floor(collectgarbage("count")),
			},
			replication = c.Loops.GetStats(),
			partIds = M.PartIds.Stats(),
			fragments = M.FragmentManager.Stats(),
			thrust = M.Thrust.Stats(),
		}
	end)

	require(script.Inspect).Init(c, Debug)
	require(script.Actions).Init(c, Debug)
	require(script.Shapes).Init(c, Debug)

	Debug.Remote.OnServerInvoke = function(player: Player, action: any, ...): any
		if not allowed(player) then
			return { ok = false, error = "not authorized" }
		end
		local fn = Debug.Handlers[action]
		if not fn then
			return { ok = false, error = "Unknown: " .. tostring(action) }
		end
		local t0 = os.clock()
		local ok, result = pcall(fn, player, ...)
		local ms = (os.clock() - t0) * 1000
		if not ok then
			Log.Warn("Debug", "%s error: %s", tostring(action), tostring(result))
			return { ok = false, error = tostring(result), ms = ms }
		end
		return { ok = true, result = result, ms = ms }
	end

	Log.Info("Debug", "DebugAPI ready (%d handlers)", count(Debug.Handlers))
end

return Debug
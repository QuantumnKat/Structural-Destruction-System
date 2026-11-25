--!strict
--!native

-- Orchestrator. Child modules receive `ctx` through Init(ctx).

local Boot: any = {}

function Boot.Start(ServerFolder: Instance): any
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService        = game:GetService("RunService")
	local Players           = game:GetService("Players")
	local Workspace         = game:GetService("Workspace")

	local Config         = require(script.Runtime.BootConfig) :: any
	local Log            = require(script.Diagnostics.Log) :: any
	local Remote         = require(script.Networking.Remote) :: any
	local State          = require(script.Runtime.State) :: any
	local MapService     = require(script.World.MapService) :: any
	local ClientRequests = require(script.Networking.ClientRequests) :: any
	local PlayerSync     = require(script.Networking.PlayerSync) :: any
	local Loops          = require(script.Runtime.Loops) :: any

	-- Destruction graph / replication modules
	local Shared      = ReplicatedStorage:WaitForChild("Shared")
	local Destruction = ServerFolder:WaitForChild("Destruction")
	local Handler     = require(Destruction:WaitForChild("ServerDestructionHandler")) :: any

	local Mods: any = {
		MapSerializer     = require(Shared:WaitForChild("Map"):WaitForChild("MapSerializer")),
		MapLoader         = require(ServerFolder:WaitForChild("Maps"):WaitForChild("MapLoader")),
		StructureGraph    = require(Destruction.Structure.StructureGraph),
		Handler           = Handler,
		ServerReplication = require(ServerFolder:WaitForChild("Replication"):WaitForChild("ServerReplication")),
		ObjectManager     = require(ServerFolder:WaitForChild("Objects"):WaitForChild("ObjectManager")),
		CollideCheck      = require(ServerFolder:WaitForChild("Objects"):WaitForChild("CollideCheck")),
		PartIndexMap      = require(Destruction.Identity.PartIndexMap),
		ForcePropagator   = require(Destruction.Structure.ForcePropagator),
		FragmentManager   = require(Destruction.Fragments.FragmentManager),
		Thrust            = require(Destruction.Fragments.FragmentThrust),
		HitShape          = require(Destruction.Geometry.HitShape),
		PartIds           = Handler.PartIds,
	}

	local ctx: any = {
		Config = Config, ServerFolder = ServerFolder,
		Services = {
			ReplicatedStorage = ReplicatedStorage, RunService = RunService,
			Players = Players, Workspace = Workspace,
		},
		Mods = Mods, Log = Log, Remote = Remote, State = State,
		MapService = MapService, Loops = Loops, Debug = nil,
	}

	-- Required init order
	Log.Init(ctx)
	Remote.Init(ctx)
	Mods.ServerReplication.UsePartIds(Mods.PartIds)
	State.Init(ctx)
	MapService.Init(ctx)
	ClientRequests.Init(ctx)
	PlayerSync.Init(ctx)
	Loops.Init(ctx)

	-- Optional legacy globals (set before map load)
	if Config.Exports.Globals then
		_G.DestructionState = {
			GetGraph            = function() return State.graph end,
			GetPhysicalPartMap  = function() return State.GetPartMap() end,
			GetActiveParts      = function() return State.ActiveParts end,
			GetReplicationEvent = function() return Remote.Event end,
			IsReady             = function() return State.graph ~= nil end,
		}
		_G.DestructionRebuild = MapService.Rebuild
		_G.DestructionHandler = Handler
		_G.DestructionReady   = false
		Log.Info("Boot", "_G.DestructionState ready")
	end

	-- Debug handlers register even if map load fails
	if Config.Debug.Enabled then
		local Debug = require(script.Diagnostics.Debug)
		ctx.Debug = Debug
		Debug.Init(ctx)
	end

	local Plugin = require(Shared:WaitForChild("Core"):WaitForChild("API"):WaitForChild("Plugin"))
	local Services = require(Shared:WaitForChild("Core"):WaitForChild("API"):WaitForChild("Services"))
	Services.Register("ServerContext", ctx)
	Plugin.Register("destruction.rebuild", function()
		return MapService.Rebuild()
	end)
	Plugin.Register("destruction.ready", function()
		return State.graph ~= nil
	end)

	ctx.Foundation = require(script.Integration.Foundation).new({Shared=Shared})
	assert(ctx.Foundation:Start(), "Foundation startup failed")
	local foundationHealth = ctx.Foundation.Commands:Dispatch("ids.inspect", {}, {tick=0,traceId="bootstrap-health"})
	assert(foundationHealth.ok, "Foundation health contract failed")

	if not MapService.Load() then
		Log.Warn("Boot", "Map load failed — server idle. Call Plugin.Call('destruction.rebuild') or debug 'rebuild'.")
	else
		if Config.Exports.Globals then _G.DestructionReady = true end
		Log.Info("Boot", "Server ready")
		Plugin.Emit("server.ready", ctx)
	end

	return ctx
end

return Boot
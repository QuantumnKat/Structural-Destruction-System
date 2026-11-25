--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Core = script.Parent :: Instance
local Client = Core.Parent :: Instance

local ClientRouter = require(Core:WaitForChild("ClientRouter") :: ModuleScript)
local ClientHandshake = require(Core:WaitForChild("ClientHandshake") :: ModuleScript)

local ClientMapLoader = require(Client:WaitForChild("Maps"):WaitForChild("ClientMapLoader") :: ModuleScript)
local ClientReplication = require(Client:WaitForChild("Replication"):WaitForChild("ClientReplication") :: ModuleScript)
local ClientDestructionHandler = require(
	Client:WaitForChild("Destruction"):WaitForChild("ClientDestructionHandler") :: ModuleScript
)
local Plugin = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("API"):WaitForChild("Plugin"))
local Services = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Core"):WaitForChild("API"):WaitForChild("Services"))

local ClientController = {}

local started = false

function ClientController.Start()
	if started then
		return
	end
	started = true

	local remote = ReplicatedStorage:WaitForChild("ReplicationEvent", 15) :: RemoteEvent?
	if not remote then
		error("[Client] ReplicationEvent missing after 15s — is the server running?")
	end

	local replication = ClientReplication.new()
	local partIndexMap: any = {}
	local pendingDebris: {any} = {}
	local router = ClientRouter.new(remote)
	router.On("MAP_DATA", function(data: any)
		ClientHandshake.MarkMapReceived()

		local _, indexMap = ClientMapLoader.BuildMap(data, replication)
		partIndexMap = indexMap
		ClientDestructionHandler.Setup(remote, replication, partIndexMap)
		print("[Client] Map loaded, destruction ready")
		Services.Register("Replication", replication)
		Plugin.Emit("client.mapLoaded", partIndexMap)

		ClientHandshake.MapLoaded()

		for _, debris in pendingDebris do
			ClientMapLoader.BuildDebris(debris, replication)
		end
		table.clear(pendingDebris)
	end)

	router.On("DYNAMIC_REPLICATE", function(data: any)
		if ClientHandshake.IsLoaded() then
			replication:ProcessBuffer(data)
		end
	end)

	router.On("CREATE_DEBRIS", function(data: any)
		if ClientHandshake.IsLoaded() then
			ClientMapLoader.BuildDebris(data, replication)
		else
			table.insert(pendingDebris, data)
		end
	end)

	router.Connect()
	ClientHandshake.Start(remote)
	Plugin.Emit("client.started")
end

return ClientController
--!strict
local network = require(game:GetService("ReplicatedStorage").Shared.Net.NetworkConf)
local chunking = network.Chunking
local defaults = table.freeze({
	MaxPackets = chunking.MaxPacketsPerChunk or 64,
	MaxBytes = chunking.MaxBytesPerChunk or 1024,
	MaxPartsPerFrame = chunking.MaxPartsPerFrame or 256,
	SpawnDelay = chunking.SpawnDelay or 0.15,
})
local limits = { MaxPackets = 512, MaxBytes = 8192, MaxPartsPerFrame = 4096, SpawnDelay = 5 }
local settings = defaults
local changed = Instance.new("BindableEvent")
local API = {}

function API.OnReplicationSettingsChanged(callback: ({[string]: number}) -> ()): RBXScriptConnection
	return changed.Event:Connect(callback)
end

function API.GetReplicationSettings()
	return settings
end

function API.ConfigureReplication(patch: {[string]: number})
	assert(type(patch) == "table", "Replication settings must be a table")
	local nextSettings = table.clone(settings) :: {[string]: number}
	for key, value in patch do
		local max = limits[key]
		local min = if key == "MaxBytes" then 28 elseif key == "SpawnDelay" then 0 else 1
		assert(max and type(value) == "number" and value >= min and value <= max
			and (key == "SpawnDelay" or value % 1 == 0), "Invalid replication setting: " .. tostring(key))
		nextSettings[key] = value
	end
	settings = table.freeze(nextSettings) :: any
	changed:Fire(settings)
	return settings
end

function API.ResetReplicationSettings()
	settings = defaults
	changed:Fire(settings)
	return settings
end

function API.IsReady(): boolean
	return require(script.Parent.Bootstrap.Runtime.State).IsReady()
end

function API.GetStats(): {[string]: number}
	return require(script.Parent.Bootstrap.Runtime.Loops).GetStats()
end

return table.freeze(API)

--!strict

local ClientHandshake = {}

ClientHandshake.RetryInterval = 2
ClientHandshake.MaxWait = 60

local remote: RemoteEvent? = nil
local started = false
local mapReceived = false
local mapLoaded = false

function ClientHandshake.Start(event: RemoteEvent)
	if started then
		return
	end
	started = true
	remote = event

	task.spawn(function()
		local waited = 0
		while not mapReceived and waited < ClientHandshake.MaxWait do
			event:FireServer("CLIENT_READY")
			task.wait(ClientHandshake.RetryInterval)
			waited += ClientHandshake.RetryInterval
		end
		if not mapReceived then
			warn("[Client] Server did not send map after", ClientHandshake.MaxWait, "seconds")
		end
	end)
end

function ClientHandshake.MarkMapReceived()
	mapReceived = true
end

function ClientHandshake.MapLoaded()
	if mapLoaded or not remote then
		return
	end
	mapLoaded = true
	remote:FireServer("MAP_LOADED")
end

function ClientHandshake.IsLoaded(): boolean
	return mapLoaded
end

return ClientHandshake
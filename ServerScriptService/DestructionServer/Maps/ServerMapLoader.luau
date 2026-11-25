--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapSerializer = require(ReplicatedStorage.Shared.Map.MapSerializer)

local ServerMapLoader = {}
local _lastPayload: any = nil

function ServerMapLoader.GetLastPayload(): any
	return _lastPayload
end

function ServerMapLoader.ProcessAndSerialize(MapLoader: any, timeout: number?): (buffer?, any?)
	local waitTime = timeout or 5

	local camera = workspace:WaitForChild("Camera", waitTime)
	if not camera then
		warn("[ServerMapLoader] Camera not found in Workspace")
		return nil, nil
	end

	local mapFolder = camera:WaitForChild("Map", waitTime)
	if not mapFolder then
		warn("[ServerMapLoader] Map not found under Camera")
		return nil, nil
	end

	local success, payload = pcall(function()
		return MapLoader.LoadMapAsChunks(mapFolder, 256)
	end)

	if not success or not payload then
		warn("[ServerMapLoader] Error: " .. tostring(payload))
		return nil, nil
	end

	local buf = MapSerializer.SerializeMap(payload.Parts)
	_lastPayload = payload
	return buf, payload
end

return ServerMapLoader
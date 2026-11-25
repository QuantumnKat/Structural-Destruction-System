--!strict

local Players = game:GetService("Players")
local STATE_READY = 1
local STATE_LOADED = 2

local ServerHandshake = {}

ServerHandshake.Timeout = 30

local states: {[Player]: number} = {}
local readyCallbacks: {(Player) -> ()} = {}
local loadedCallbacks: {(Player) -> ()} = {}
local remote: RemoteEvent? = nil

local function watch(player: Player)
	task.delay(ServerHandshake.Timeout, function()
		if player.Parent and states[player] == nil then
			warn("[Handshake]", player.Name, "did not send CLIENT_READY after", ServerHandshake.Timeout, "seconds")
		end
	end)
end

function ServerHandshake.Init(event: RemoteEvent)
	if remote then
		return
	end
	remote = event

	event.OnServerEvent:Connect(function(player: Player, action: unknown)
		if action == "CLIENT_READY" then
			if states[player] ~= nil then
				return
			end
			states[player] = STATE_READY
			for _, callback in readyCallbacks do
				task.spawn(callback, player)
			end
		elseif action == "MAP_LOADED" then
			if states[player] ~= STATE_READY then
				return
			end
			states[player] = STATE_LOADED
			for _, callback in loadedCallbacks do
				task.spawn(callback, player)
			end
		end
	end)

	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
end

function ServerHandshake.OnClientReady(callback: (Player) -> ())
	table.insert(readyCallbacks, callback)
end

function ServerHandshake.OnMapLoaded(callback: (Player) -> ())
	table.insert(loadedCallbacks, callback)
end

function ServerHandshake.IsReady(player: Player): boolean
	return states[player] ~= nil
end

function ServerHandshake.IsLoaded(player: Player): boolean
	return states[player] == STATE_LOADED
end

function ServerHandshake.Reset(player: Player)
	states[player] = nil
end

function ServerHandshake.FireLoaded(action: string, data: any)
	local event = remote
	if not event then
		return
	end
	for player, state in states do
		if state == STATE_LOADED then
			event:FireClient(player, action, data)
		end
	end
end

return ServerHandshake
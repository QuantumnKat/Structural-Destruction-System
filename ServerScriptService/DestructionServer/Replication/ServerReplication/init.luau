--!strict
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local Cache = require(script.PartCache)
local writeSnapshot = require(script.SnapshotWriter)
local getCharacterRoot = require(script.CharacterView)
local AOI = require(ReplicatedStorage.Shared.Net.Interest.AOI)
local LOD = require(ReplicatedStorage.Shared.Net.Interest.LOD)
local API = require(script.Parent.Parent.API)

local PACKET_BYTES     = 16
local TRAILER_BYTES    = 12
local CLEANUP_INTERVAL = 5.0
local SLEEP_INTERVAL   = 2.0

local mathmin   = math.min
local mathfloor = math.floor
local mathhuge  = math.huge
local osclock   = os.clock
local bcreate   = buffer.create
local blen      = buffer.len

local gate: ((Player) -> boolean)? = nil

local ServerReplication = {}
ServerReplication.__index = ServerReplication

local sharedPartIds: any = nil
function ServerReplication.UsePartIds(provider: any)
	sharedPartIds = provider
end

function ServerReplication.UseGate(fn: ((Player) -> boolean)?)
	gate = fn
end

function ServerReplication.new()
	local self: any = setmetatable({}, ServerReplication)
	self.clients = setmetatable({}, { __mode = "k" })
	self.CleanupTimer = 0
	self._partIds = sharedPartIds

	self._tick = 0
	self._scratch = bcreate(0)
	self._stamp = {}
	self._valid = {}
	self._id = {}
	self._pos = {}
	self._sleep = {}
	self._selected = {}
	self._born = {}
	return self
end

function ServerReplication:Step(deltaTime: number, activeParts: { BasePart }): { [Player]: buffer }
	local clientPayloads: { [Player]: buffer } = {}

	self.CleanupTimer += deltaTime
	if self.CleanupTimer >= CLEANUP_INTERVAL then
		self.CleanupTimer = 0
		Cache.Cleanup(self, activeParts)
	end

	local n = #activeParts
	if n == 0 then return clientPayloads end

	local settings = API.GetReplicationSettings()
	local maxByBytes = mathfloor((settings.MaxBytes - TRAILER_BYTES) / PACKET_BYTES)
	local limit = mathmin(settings.MaxPackets, maxByBytes)
	if limit <= 0 then return clientPayloads end

	local now = osclock()
	local stamp = workspace:GetServerTimeNow()
	local slack = deltaTime * 0.5
	local scan = mathmin(n, settings.MaxPartsPerFrame)

	local tick: number = self._tick + 1
	self._tick = tick

	local need = n * PACKET_BYTES
	if blen(self._scratch) < need then
		self._scratch = bcreate(mathfloor(need * 1.5))
	end
	local scratch: buffer = self._scratch

	local ids, poss, sleeps = self._id, self._pos, self._sleep
	local selected = self._selected
	local born = self._born
	local clients = self.clients
	local players = Players:GetPlayers()
	for pi = 1, #players do
		local client = players[pi]
		if gate and not gate(client) then continue end
		local root = getCharacterRoot(client)
		if not root then continue end
		local focal = root.Position

		local st = clients[client]
		if not st then
			st = { Cursor = 0, Last = {}, SleepSent = {} }
			clients[client] = st
		end
		local last, sleepSent = st.Last, st.SleepSent
		local cursor: number = st.Cursor

		local count = 0
		local processed = 0

		while processed < scan and count < limit do
			cursor = cursor % n + 1
			processed += 1

			if not Cache.Prepare(self, cursor, activeParts[cursor], tick) then continue end

			local partId: number = ids[cursor]
			local diff: Vector3 = poss[cursor] - focal
			local distSq = diff:Dot(diff)
			local lastT = last[partId]

			local bornAt = born[partId]
			if bornAt and now - bornAt < settings.SpawnDelay then
				continue
			end

			local relevant = AOI.InRangeHysteresis(distSq, lastT ~= nil)
			if not relevant then
				last[partId] = nil
				sleepSent[partId] = nil
				continue
			end

			local send = false

			if sleeps[cursor] then
				if not sleepSent[partId] or lastT == nil or now - lastT >= SLEEP_INTERVAL then
					send = true
					sleepSent[partId] = true
				end
			else
				sleepSent[partId] = nil
				local period = LOD.GetPeriod(distSq)
				if period < mathhuge and (lastT == nil or now - lastT >= period - slack) then
					send = true
				end
			end

			if send then
				last[partId] = now
				count += 1
				selected[count] = cursor
			end
		end

		st.Cursor = cursor

		if count > 0 then
			clientPayloads[client] = writeSnapshot(scratch, selected, count, stamp, PACKET_BYTES, TRAILER_BYTES)
		end
	end

	return clientPayloads
end

return ServerReplication
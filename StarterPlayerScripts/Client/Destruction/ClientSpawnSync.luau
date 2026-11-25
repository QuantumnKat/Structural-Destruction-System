--!strict
-- EditorSync: refactor-v1
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local SpawnCodec = require(ReplicatedStorage.Shared.Destruction.SpawnCodec)
local NetworkConf: any = require(ReplicatedStorage.Shared.Net.NetworkConf)

local Cfg: any = NetworkConf.Spawn or {}
local PROXY_ENABLED: boolean = Cfg.ProxyEnabled ~= false
local PROXY_DELAY: number    = Cfg.ProxyDelay or 1.5
local MAX_PENDING: number    = Cfg.MaxPending or 4096
local GIVE_UP: number        = Cfg.GiveUp or 15

local ClientSpawnSync = {}

local pending: { [number]: any } = {}
local pendingCount = 0
local rep: any = nil
local folder: Folder? = nil
local stats = { proxies = 0, resolved = 0, gaveUp = 0, dropped = 0 }

local function getFolder(): Folder
	if folder and folder.Parent then return folder end
	local f = workspace:FindFirstChild("ClientDebris")
	if not f or not f:IsA("Folder") then
		f = Instance.new("Folder")
		f.Name = "ClientDebris"
		f.Parent = workspace
	end
	folder = f :: Folder
	return folder :: Folder
end

local function removePending(id: number)
	if pending[id] ~= nil then
		pending[id] = nil
		pendingCount -= 1
	end
end

local function createProxy(r: any)
	local p = Instance.new("Part")
	p.Name = "Proxy"
	p.Anchored = true
	p.CanCollide = r.canCollide
	p.CanTouch = false
	p.Massless = false
	p.Material = r.material
	p.Color = r.color
	p.Transparency = r.transparency
	if r.shape == 1 then
		p.Shape = Enum.PartType.Ball
	elseif r.shape == 2 then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Size = r.size
	p.CFrame = r.cf
	p:SetAttribute("ObjectId", r.id)
	p:SetAttribute("Proxy", true)
	p.Parent = getFolder()
	rep:RegisterPart(r.id, p)
	stats.proxies += 1
end

function ClientSpawnSync.OnSpawn(buf: buffer)
	if not rep then return end
	local n = SpawnCodec.Count(buf)
	if buffer.len(buf) < 2 + n * SpawnCodec.RecordBytes then return end
	local now = os.clock()

	for i = 0, n - 1 do
		local r = SpawnCodec.Read(buf, 2 + i * SpawnCodec.RecordBytes)
		local id: number = r.id
		local existing = rep.DynamicParts[id]
		if existing and existing.Parent then
			continue
		end
		if rep:_tryResolve(id, now) then
			stats.resolved += 1
			continue
		end
		if r.immediate and PROXY_ENABLED and not r.noProxy then
			createProxy(r)
			continue
		end
		if pending[id] == nil then
			if pendingCount >= MAX_PENDING then
				stats.dropped += 1
				continue
			end
			pendingCount += 1
		end
		pending[id] = { rec = r, t0 = now, due = now + PROXY_DELAY }
	end
end

function ClientSpawnSync.OnDespawn(buf: buffer)
	if not rep then return end
	local ids = SpawnCodec.DecodeIds(buf)
	for i = 1, #ids do
		local id = ids[i]
		removePending(id)
		local part = rep.DynamicParts[id]
		if part then
			rep:ForgetPart(part)
			if part.Parent then part:Destroy() end
		end
	end
end

local stepConnection: RBXScriptConnection? = nil

function ClientSpawnSync.Setup(clientRep: any)
	if rep then return end
	rep = clientRep

	local acc = 0
	stepConnection = RunService.Heartbeat:Connect(function(dt)
		if pendingCount == 0 then acc = 0; return end
		acc += dt
		if acc < 0.25 then return end
		acc = 0
		local now = os.clock()
		for id, p in pairs(pending) do
			local part = rep.DynamicParts[id]
			if part and part.Parent then
				removePending(id)
			elseif now >= p.due then
				local r = p.rec
				if rep:_tryResolve(id, now) then
					stats.resolved += 1
					removePending(id)
				elseif PROXY_ENABLED and not r.noProxy then
					createProxy(r)
					removePending(id)
				elseif now - p.t0 > GIVE_UP then
					stats.gaveUp += 1
					removePending(id)
				end
			end
		end
	end)
end

function ClientSpawnSync.Destroy()
 if stepConnection then stepConnection:Disconnect(); stepConnection = nil end
 table.clear(pending)
 pendingCount = 0
 rep = nil
end

function ClientSpawnSync.Stats(): { [string]: number }
	return {
		Pending = pendingCount, Proxies = stats.proxies, Resolved = stats.resolved,
		GaveUp = stats.gaveUp, Dropped = stats.dropped,
	}
end

return ClientSpawnSync

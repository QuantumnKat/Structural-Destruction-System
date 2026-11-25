--!strict
--!native

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local SpawnCodec    = require(ReplicatedStorage.Shared.Destruction.SpawnCodec)
local Conf: any     = require(script.Parent.Parent.Fragments.FragmentConf)
local Constants     = require(script.Parent.Parent.Support.Constants)
local ObjectManager = require(script.Parent.Parent.Parent.Objects.ObjectManager)
local ObjectConf    = require(script.Parent.Parent.Parent.Objects.ObjectConf)

local SLEEP_FLAG = 2147483648
local REC = SpawnCodec.RecordBytes
local I: any = Conf.Ids

local PartIds = {}

local S: any = {
	inited = false, event = nil, active = nil,
	nextExtra = Conf.ExtraIdBase,
	announced = setmetatable({}, { __mode = "k" }), -- [part] = last announced ObjectId
	owner = setmetatable({}, { __mode = "v" }),     -- [id] = part
	liveIds = {},
	queue = {}, queueImm = {}, qHead = 1, qTail = 0, debrisCounter = 0,
	despawn = {},
	scanKey = nil,
	stats = { assigned = 0, collisions = 0, announced = 0, despawned = 0, dropped = 0, healed = 0 },
}

------------------------------------------------------------------
-- ID
------------------------------------------------------------------
local function newExtraId(): number
	local id: number = S.nextExtra
	S.nextExtra += 1
	return id
end

function PartIds.Assign(part: BasePart): number
	local oid = part:GetAttribute("ObjectId")
	local id: number
	if type(oid) == "number" and oid < SLEEP_FLAG then
		id = oid
	else
		local pid = part:GetAttribute("PartIndex")
		if type(pid) == "number" then
			id = pid + Constants.FALLING_ID_OFFSET
		else
			id = ObjectManager.GetPartId(part) or newExtraId()
		end
		part:SetAttribute("ObjectId", id)
		S.stats.assigned += 1
	end
	if not CollectionService:HasTag(part, I.Tag) then
		CollectionService:AddTag(part, I.Tag)
	end
	return id
end

local function enqueue(part: BasePart, immediate: boolean?): boolean
 if S.qTail - S.qHead + 1 >= I.MaxQueue then
  S.stats.dropped += 1
  S.announced[part] = nil -- allow Touch to retry instead of permanently losing this spawn
  return false
 end
 S.qTail += 1
 S.queue[S.qTail] = part
 S.queueImm[S.qTail] = immediate == true
 return true
end

function PartIds.Touch(part: BasePart, oid: any): any
	local valid = type(oid) == "number" and oid < SLEEP_FLAG
	if valid and S.announced[part] == oid then
		return oid
	end

	if not valid then
		if I.AutoAssign == false then return oid end
		oid = PartIds.Assign(part)
		S.stats.healed += 1
	elseif not CollectionService:HasTag(part, I.Tag) then
		CollectionService:AddTag(part, I.Tag)
	end

	local other = S.owner[oid]
	if other ~= nil and other ~= part and other.Parent ~= nil then
		S.stats.collisions += 1
		if I.Audit.AutoFix and type(part:GetAttribute("PartIndex")) ~= "number" then
			oid = newExtraId()
			part:SetAttribute("ObjectId", oid)
		end
	end

	S.announced[part] = oid
	S.owner[oid] = part
	S.liveIds[oid] = true
	if I.AnnounceSpawns ~= false then
		enqueue(part)
	end
	return oid
end

function PartIds.NewDebrisId(): number
	local base = (Constants :: any).DEBRIS_ID_OFFSET
	if type(base) ~= "number" or base + 999999 >= SLEEP_FLAG then
		return newExtraId()
	end
	local n: number = S.debrisCounter
	for _ = 1, 64 do
		n = n % 999999 + 1
		local id = base + n
		local o: BasePart? = S.owner[id]
		if o == nil or o.Parent == nil or o:GetAttribute("ObjectId") ~= id then
			S.debrisCounter = n
			return id
		end
	end
	S.debrisCounter = n
	return newExtraId()
end

function PartIds.Register(part: BasePart, id: number)
	if not CollectionService:HasTag(part, I.Tag) then
		CollectionService:AddTag(part, I.Tag)
	end
	S.announced[part] = id
	S.owner[id] = part
	S.liveIds[id] = true
end

function PartIds.Announce(part: BasePart, immediate: boolean?)
	local id = PartIds.Assign(part)
	S.announced[part] = id
	S.owner[id] = part
	S.liveIds[id] = true
	enqueue(part, immediate)
end

------------------------------------------------------------------
-- SPAWN / DESPAWN
------------------------------------------------------------------
local function buildSpawnBuffer(parts: { BasePart }, from: number, to: number, imm: { boolean }?): buffer?
	local buf = buffer.create(2 + (to - from + 1) * REC)
	local written = 0
	for i = from, to do
		local p = parts[i]
		if p and p.Parent then
			local id = p:GetAttribute("ObjectId")
			if type(id) == "number" then
				SpawnCodec.Write(buf, 2 + written * REC, p, id, type(p:GetAttribute("PartIndex")) == "number", imm ~= nil and imm[i] == true)
				written += 1
			end
		end
	end
	if written == 0 then return nil end
	buffer.writeu16(buf, 0, written)
	if written == to - from + 1 then return buf end
	local exact = buffer.create(2 + written * REC)
	buffer.copy(exact, 0, buf, 0, 2 + written * REC)
	return exact
end

local function flushSpawns()
	local ev: RemoteEvent? = S.event
	if not ev then return end
	local avail = S.qTail - S.qHead + 1
	if avail <= 0 then return end

	local q: { BasePart } = S.queue
	local imm: { boolean } = S.queueImm
	local take = math.min(avail, I.MaxSpawnPerStep)
	local from = S.qHead
	local to = from + take - 1
	local buf = buildSpawnBuffer(q, from, to, imm)
	for i = from, to do
		q[i] = nil
		imm[i] = nil
	end
	S.qHead = to + 1
	if S.qHead > S.qTail then
		S.queue = {}
		S.queueImm = {}
		S.qHead = 1
		S.qTail = 0
	end
	if buf then
		S.stats.announced += SpawnCodec.Count(buf)
		ev:FireAllClients("SPAWN_PARTS", buf)
	end
end

local function scanDespawn()
	local live: { [number]: boolean } = S.liveIds
	local k = S.scanKey
	for _ = 1, I.ScanBudget do
		k = next(live, k)
		if k == nil then break end
		local part: BasePart? = S.owner[k]
		if part == nil or part.Parent == nil or part:GetAttribute("ObjectId") ~= k then
			live[k] = nil
			if part and part.Parent == nil then S.announced[part] = nil end
			S.despawn[#S.despawn + 1] = k
			S.stats.despawned += 1
		end
	end
	S.scanKey = k
end

local function flushDespawn()
	local ev: RemoteEvent? = S.event
	local d: { number } = S.despawn
	if not ev or #d == 0 then return end
	local i = 1
	while i <= #d do
		local j = math.min(i + 1023, #d)
		ev:FireAllClients("DESPAWN_PARTS", SpawnCodec.EncodeIds(d, i, j))
		i = j + 1
	end
	S.despawn = {}
end

function PartIds.SendAll(player: Player)
	local ev: RemoteEvent? = S.event
	local active: { BasePart }? = S.active
	if not ev or not active then return end
	local batch: { BasePart } = {}
	local function send()
		local imm: { boolean } = {}
		for i = 1, #batch do imm[i] = true end
		local buf = buildSpawnBuffer(batch, 1, #batch, imm)
		if buf then ev:FireClient(player, "SPAWN_PARTS", buf) end
		batch = {}
	end
	for i = 1, #active do
		local p = active[i]
		if p and p.Parent and type(p:GetAttribute("ObjectId")) == "number" then
			batch[#batch + 1] = p
			if #batch >= 200 then send() end
		end
	end
	if #batch > 0 then send() end
end

------------------------------------------------------------------
-- AUDIT
------------------------------------------------------------------
function PartIds.Audit(fix: boolean?): { [string]: any }
	local active: { BasePart }? = S.active
	local rep: { [string]: any } = {
		total = 0, detached = 0, missingId = 0, badId = 0, duplicate = 0,
		untagged = 0, orphans = 0, fixed = 0, samples = {},
	}
	if not active then return rep end

	local seen: { [number]: BasePart } = {}
	for i = 1, #active do
		local p = active[i]
		if not p or p.Parent == nil then
			rep.detached += 1
			continue
		end
		rep.total += 1

		local oid = p:GetAttribute("ObjectId")
		local hasPI = type(p:GetAttribute("PartIndex")) == "number"
		local problem: string? = nil

		if type(oid) ~= "number" then
			rep.missingId += 1
			problem = "missingId"
			if fix then PartIds.Assign(p); rep.fixed += 1 end
		elseif oid >= SLEEP_FLAG then
			rep.badId += 1
			problem = "badId"
			if fix then
				p:SetAttribute("ObjectId", newExtraId())
				PartIds.Assign(p)
				rep.fixed += 1
			end
		else
			local o = seen[oid]
			if o and o ~= p then
				rep.duplicate += 1
				problem = "duplicate"
				if fix and not hasPI then
					p:SetAttribute("ObjectId", newExtraId())
					PartIds.Assign(p)
					rep.fixed += 1
				end
			end
			seen[oid] = p
			if not CollectionService:HasTag(p, I.Tag) then
				rep.untagged += 1
				if fix then CollectionService:AddTag(p, I.Tag); rep.fixed += 1 end
			end
			if not hasPI and ObjectManager.GetPartId(p) == nil then
				rep.orphans += 1
				problem = problem or "orphan"
			end
		end

		if problem and #rep.samples < 5 then
			rep.samples[#rep.samples + 1] = problem .. ": " .. p:GetFullName() .. " (" .. p.ClassName .. ")"
		end
	end
	return rep
end

------------------------------------------------------------------
-- INIT
------------------------------------------------------------------
function PartIds.Init(replicationEvent: RemoteEvent?, ActiveParts: { BasePart })
	if S.inited then return end
	S.inited = true
	S.event = replicationEvent
	S.active = ActiveParts

	local maxPool = (ObjectConf.GetConfig().MaxInstances or 1000)
	local offset: number = Constants.FALLING_ID_OFFSET
	if offset <= maxPool then
		warn(("[PartIds] FALLING_ID_OFFSET (%d) <= MaxInstances (%d): map part ids will collide with debris pool ids; increase the offset (e.g. 1_000_000)."):format(offset, maxPool))
	end
	if offset + 1_000_000 > Conf.ExtraIdBase and offset < Conf.ExtraIdBase then
		warn("[PartIds] vùng id rơi (offset..offset+PartIndex) có thể chạm ExtraIdBase; hãy giảm offset hoặc tăng ExtraIdBase (< 2^31).")
	end

	local accFlush, accAudit = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		accFlush += dt
		accAudit += dt
		if accFlush >= I.SpawnFlushInterval then
			accFlush = 0
			flushSpawns()
			scanDespawn()
			flushDespawn()
		end
		if I.Audit.Enabled and accAudit >= I.Audit.Interval then
			accAudit = 0
			local r = PartIds.Audit(I.Audit.AutoFix)
			local issues = r.missingId + r.badId + r.duplicate + r.untagged + r.orphans
			if I.Audit.Warn and issues > 0 then
				warn(("[PartIds] audit: total=%d missingId=%d badId=%d duplicate=%d untagged=%d orphans=%d fixed=%d detached=%d"):format(
					r.total, r.missingId, r.badId, r.duplicate, r.untagged, r.orphans, r.fixed, r.detached))
				for _, s in ipairs(r.samples) do warn("  " .. s) end
			end
		end
	end)
end

function PartIds.Stats(): { [string]: number }
	local live = 0
	for _ in pairs(S.liveIds) do live += 1 end
	local s = S.stats
	return {
		Live = live, Assigned = s.assigned, Healed = s.healed, Collisions = s.collisions,
		Announced = s.announced, Despawned = s.despawned, Dropped = s.dropped,
		Queued = S.qTail - S.qHead + 1,
	}
end

return PartIds

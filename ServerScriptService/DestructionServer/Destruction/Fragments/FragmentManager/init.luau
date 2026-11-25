--!strict
-- EditorSync: refactor-v1
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Quantize      = require(ReplicatedStorage.Shared.World.Spatial.Quantize)
local SnapshotCodec = require(ReplicatedStorage.Shared.Destruction.SnapshotCodec)
local Conf: any     = require(script.Parent.Parent.Fragments.FragmentConf)
local EventLog      = require(script.Parent.Parent.Diagnostics.EventLog)
local HitShapeMod   = require(script.Parent.Parent.Geometry.HitShape)
local Constants     = require(script.Parent.Parent.Support.Constants)
local ObjectManager = require(script.Parent.Parent.Parent.Objects.ObjectManager)
local ObjectConf    = require(script.Parent.Parent.Parent.Objects.ObjectConf)
local PartIds       = require(script.Parent.Parent.Identity.PartIds)

local ins       = table.insert
local osclock   = os.clock
local mathmax   = math.max
local mathmin   = math.min
local mathclamp = math.clamp
local random    = math.random

local FragmentManager = {}
FragmentManager.Config = Conf

local S: any = {
	inited = false,
	graph = nil, event = nil, active = nil,
	maxIdx = 0, state = nil, log = nil,
	nextFid = 1, nextExtraId = Conf.ExtraIdBase,
	snapshots = {}, dirty = 0, lastSnap = 0, cursor = 0,
}

------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------
local function mark(idx: number, st: number)
	local b: buffer? = S.state
	if not b or idx < 1 then return end
	if idx > S.maxIdx then
		local newMax = mathmax(idx, math.floor(S.maxIdx * 1.25) + 16)
		local nb = buffer.create(SnapshotCodec.StateBytes(newMax))
		buffer.copy(nb, 0, b, 0, buffer.len(b))
		S.state = nb
		S.maxIdx = newMax
		b = nb
	end
	SnapshotCodec.SetState(b :: buffer, idx, st)
	S.dirty += 1
end

local function removeFromActive(part: BasePart)
	local active: { BasePart } = S.active
	for i = #active, 1, -1 do
		if active[i] == part then
			local last = #active
			active[i] = active[last]
			active[last] = nil
		end
	end
end

local function breakWeldsOf(part: BasePart)
	local joints = part:GetJoints()
	for i = 1, #joints do
		if joints[i]:IsA("WeldConstraint") then
			joints[i]:Destroy()
		end
	end
end

local function ensureId(part: BasePart): number
	return PartIds.Assign(part)
end

local function releasePart(part: BasePart)
	local ok = ObjectManager.ReleaseOrDestroy(part)
	if not ok and part.Parent then
		part:Destroy()
	end
end

local function removeVoxel(part: BasePart, logAsVanish: boolean)
	local id = part:GetAttribute("ObjectId")
	local pid = part:GetAttribute("PartIndex")
	breakWeldsOf(part)
	removeFromActive(part)
	if type(pid) == "number" then
		mark(pid, 2)
		if S.event then S.event:FireAllClients("DESTROY_PART", pid) end
		if S.log then S.log:Destroy(pid) end
	elseif logAsVanish and S.log and type(id) == "number" then
		S.log:Vanish(id)
	end
	releasePart(part)
end

local function wakeAssembly(part: BasePart)
	if part:GetAttribute("IsSleeping") then
		local conn = part:GetConnectedParts(true)
		for i = 1, #conn do
			ObjectManager.WakePart(conn[i])
		end
		ObjectManager.WakePart(part)
	end
end

local function hpOf(part: BasePart): number
	local a = part:GetAttribute("HP")
	if type(a) == "number" then return a end
	local s = part.Size
	local vol = s.X * s.Y * s.Z
	local rule: any = ObjectConf.GetMaterialRule(part.Material)
	return mathmax(10, 100 * (rule.HpMultiplier or 1) * (vol / 8) ^ (1 / 3))
end

------------------------------------------------------------------
-- INIT
------------------------------------------------------------------
function FragmentManager.IsActive(): boolean
	return S.inited
end

function FragmentManager.Init(graph: any, replicationEvent: RemoteEvent?, ActiveParts: { BasePart })
	if S.inited or Conf.Enabled == false then return end
	S.inited = true
	S.graph = graph
	S.event = replicationEvent
	S.active = ActiveParts

	local maxIdx = 0
	for idx in pairs(graph.Nodes) do
		if idx > maxIdx then maxIdx = idx end
	end
	S.maxIdx = maxIdx
	S.state = buffer.create(SnapshotCodec.StateBytes(maxIdx))
	if Conf.Log.Enabled then
		S.log = EventLog.new(Conf.Log.SegmentBytes, Conf.Log.Segments)
	end
	S.lastSnap = osclock()

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= Conf.Vanish.StepInterval then
			local d = acc
			acc = 0
			FragmentManager.Step(d)
		end
	end)
end

function FragmentManager.SetGraph(graph: any)
	if not S.inited or S.graph == graph then return end
	S.graph = graph
	local maxIdx = 0
	for idx in pairs(graph.Nodes) do
		if idx > maxIdx then maxIdx = idx end
	end
	S.maxIdx = maxIdx
	S.state = buffer.create(SnapshotCodec.StateBytes(maxIdx))
	S.snapshots = {}
	S.dirty = 0
	S.lastSnap = osclock()
end

------------------------------------------------------------------
-- EVENT LOG
------------------------------------------------------------------
function FragmentManager.LogHit(shape: any, force: number)
	local log = S.log
	if not log then return end
	local code = EventLog.ShapeCode[shape.Type] or 0
	local p1, p2, p3 = 0, 0, 0
	local t = shape.Type
	if t == "Sphere" then
		p1 = shape.Radius or 1
	elseif t == "Box" then
		local sz: Vector3 = shape.Size or Vector3.new(2, 2, 2)
		p1, p2, p3 = sz.X, sz.Y, sz.Z
	elseif t == "Cone" then
		p1, p2 = shape.Length or 8, shape.HalfAngle or 30
	else
		p1, p2 = shape.Radius or 1, shape.Length or 4
	end
	local cf: CFrame = shape.CFrame
	log:Hit(code, cf.Position, force, cf.LookVector, p1, p2, p3)
	S.dirty += 1
end

function FragmentManager.GetLog(): any
	return S.log
end

function FragmentManager.DecodeEvent(kind: number, buf: buffer, off: number): { [string]: any }
	return EventLog.Decode(kind, buf, off)
end

function FragmentManager.ExportLog(): string?
	if S.log then return S.log:Export() end
	return nil
end

------------------------------------------------------------------
------------------------------------------------------------------
FragmentManager.PlanFragments = require(script.FragmentPlanner)({
 State = S, Config = Conf, Mark = mark, EnsureId = ensureId,
})

------------------------------------------------------------------
------------------------------------------------------------------
FragmentManager.HitFragments = require(script.FragmentHits)({
 State = S, Config = Conf, ObjectManager = ObjectManager, PartIds = PartIds, HitShape = HitShapeMod,
 HpOf = hpOf, WakeAssembly = wakeAssembly, RemoveVoxel = removeVoxel,
})

------------------------------------------------------------------
-- SNAPSHOT
------------------------------------------------------------------
local SnapshotAPI = require(script.FragmentSnapshots)({
 State = S, Config = Conf, SnapshotCodec = SnapshotCodec, Quantize = Quantize, PartIds = PartIds,
})
FragmentManager.CaptureSnapshot = SnapshotAPI.CaptureSnapshot
FragmentManager.GetSnapshot = SnapshotAPI.GetSnapshot
FragmentManager.SendSnapshot = SnapshotAPI.SendSnapshot

------------------------------------------------------------------
------------------------------------------------------------------
FragmentManager.Step = require(script.FragmentLifecycle)({
 State = S, Config = Conf, SnapshotCodec = SnapshotCodec, Mark = mark,
 BreakWeldsOf = breakWeldsOf, ReleasePart = releasePart, CaptureSnapshot = FragmentManager.CaptureSnapshot,
})

function FragmentManager.Stats(): { [string]: any }
	local snapBytes = 0
	for _, s in ipairs(S.snapshots) do
		snapBytes += buffer.len(s.data)
	end
	return {
		Active = S.inited,
		StateBytes = if S.state then buffer.len(S.state) else 0,
		Snapshots = #S.snapshots,
		SnapshotBytes = snapBytes,
		Log = if S.log then S.log:Stats() else nil,
		NextFragmentId = S.nextFid,
	}
end

return FragmentManager

--!strict
-- EditorSync: refactor-v1
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Quantize          = require(ReplicatedStorage.Shared.World.Spatial.Quantize)

local InterestConf      = require(ReplicatedStorage.Shared.Net.Interest.InterestConf)
local AOIConf = InterestConf.GetConfig("AOI")

local USE_CAMERA: boolean = AOIConf.UseCameraAsFocalPoint == true

local osclock   = os.clock
local mathclamp = math.clamp
local mathsqrt  = math.sqrt
local mathexp   = math.exp
local mathabs   = math.abs
local readu32   = buffer.readu32
local readi16   = buffer.readi16
local readf64   = buffer.readf64
local ins       = table.insert

local ZERO = Vector3.zero

local PACKET_BYTES  = 16
local TRAILER_BYTES = 12
local SLEEP_FLAG    = 2147483648
local SETTLE_EPS_SQ = 1e-4

local Settings = require(script.ReplicationSettings)
local BASE = Settings.BASE
local TierConf = Settings.TierConf
local Tiers = Settings.Tiers
local LOCAL_ANCHOR = Settings.LOCAL_ANCHOR
local SKIP_UNCHANGED = Settings.SKIP_UNCHANGED
local TARGET_TTL = Settings.TARGET_TTL
local SWEEP_INTERVAL = Settings.SWEEP_INTERVAL
local LOD_RECHECK = Settings.LOD_RECHECK
local UNREG_TTL = Settings.UNREG_TTL
local RESOLVE_COOLDOWN = Settings.RESOLVE_COOLDOWN
local DYN_TAG = Settings.DYN_TAG
local BULK_INITIAL_SIZE = Settings.BULK_INITIAL_SIZE
local BULK_MODE = Settings.BULK_MODE
local function getTierIndex(distance: number): number
	for i = 1, #Tiers do
		local md = Tiers[i].MaxDistance
		if md == nil or distance <= md then
			return i
		end
	end
	return #Tiers
end

local function getFocalPosition(client: Player?): Vector3?
	if USE_CAMERA then
		local cam = workspace.CurrentCamera
		if cam then return cam.CFrame.Position end
	end
	if client then
		local char = client.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				return root.Position
			end
		end
	end
	if not USE_CAMERA then
		local cam = workspace.CurrentCamera
		if cam then return cam.CFrame.Position end
	end
	return nil
end

local SnapshotBuffer = require(script.SnapshotBuffer)
local pushSnap, sampleBuffer = SnapshotBuffer.Push, SnapshotBuffer.Sample
local TargetState = require(script.TargetState)

local ClientReplication = {}
ClientReplication.__index = ClientReplication

function ClientReplication.new()
	local self: any = setmetatable({}, ClientReplication)
	self.DynamicParts = {}
	self.Targets = {}
	self._destroyed = false
	self.LocalPlayer = Players.LocalPlayer
	self._bulkParts   = table.create(BULK_INITIAL_SIZE)
	self._bulkCFrames = table.create(BULK_INITIAL_SIZE)
	self._bulkCount   = 0
	self._connections = {}
	self._sweepTimer  = 0
	self._partIds     = setmetatable({}, { __mode = "k" })
	self._watchers    = {}
	self._decay       = {}

	self._clockOffset = nil :: number?
	self._lastArrival = nil :: number?
	self._lastServerT = 0
	self._jitter      = 0
	self._resolver    = nil
	self._resolveAt   = {}

	ins(self._connections, workspace.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			local oid = desc:GetAttribute("ObjectId")
			if typeof(oid) == "number" then
				self:RegisterPart(oid, desc)
			end
		end
	end))

	ins(self._connections, workspace.DescendantRemoving:Connect(function(desc)
		if desc:IsA("BasePart") then
			self:ForgetPart(desc)
		end
	end))

	ins(self._connections, RunService.RenderStepped:Connect(function(dt)
		self:UpdateLerp(dt)
	end))

	ins(self._connections, CollectionService:GetInstanceAddedSignal(DYN_TAG):Connect(function(inst)
		if inst:IsA("BasePart") then self:WatchPart(inst) end
	end))
	for _, inst in ipairs(CollectionService:GetTagged(DYN_TAG)) do
		if inst:IsA("BasePart") then self:WatchPart(inst) end
	end

	if BASE.ScanOnStart ~= false then
		task.spawn(function()
			local list = workspace:GetDescendants()
			for i = 1, #list do
				if self._destroyed then return end
				local d = list[i]
				if d:IsA("BasePart") then
					local oid = d:GetAttribute("ObjectId")
					if typeof(oid) == "number" then
						self:WatchPart(d)
					end
				end
				if i % 2000 == 0 then task.wait() end
			end
		end)
	end

	return self
end

require(script.ReplicationRegistry)(ClientReplication, { LOCAL_ANCHOR = LOCAL_ANCHOR, RESOLVE_COOLDOWN = RESOLVE_COOLDOWN, sampleBuffer = sampleBuffer, osclock = osclock })

require(script.ReplicationIngest)(ClientReplication, { BASE = BASE, LOCAL_ANCHOR = LOCAL_ANCHOR, SETTLE_EPS_SQ = SETTLE_EPS_SQ, newTarget = TargetState.New, initialDelay = TargetState.InitialDelay, seedOffset = TargetState.SeedOffset, pushSnap = pushSnap, sampleBuffer = sampleBuffer, ZERO = ZERO, mathclamp = mathclamp, mathabs = mathabs, readu32 = readu32, readf64 = readf64, readi16 = readi16, PACKET_BYTES = PACKET_BYTES, TRAILER_BYTES = TRAILER_BYTES, SLEEP_FLAG = SLEEP_FLAG, Quantize = Quantize, osclock = osclock })

require(script.ReplicationRender)(ClientReplication, { SWEEP_INTERVAL = SWEEP_INTERVAL, UNREG_TTL = UNREG_TTL, TARGET_TTL = TARGET_TTL, TierConf = TierConf, LOD_RECHECK = LOD_RECHECK, SKIP_UNCHANGED = SKIP_UNCHANGED, BULK_MODE = BULK_MODE, getFocalPosition = getFocalPosition, getTierIndex = getTierIndex, sampleBuffer = sampleBuffer, ZERO = ZERO, osclock = osclock, mathexp = mathexp, mathsqrt = mathsqrt })

function ClientReplication:BindToRemote(cframeStreamRemote: RemoteEvent)
	if not cframeStreamRemote then return end
	local conn = cframeStreamRemote.OnClientEvent:Connect(function(buf)
		if typeof(buf) == "buffer" then
			self:ProcessBuffer(buf)
		elseif typeof(buf) == "string" then
			self:ProcessBuffer(buffer.fromstring(buf))
		end
	end)
	ins(self._connections, conn)
end

function ClientReplication:ClearAll()
	for _, part in pairs(self.DynamicParts) do
		if part and part.Parent then
			part:Destroy()
		end
	end
	for _, c in pairs(self._watchers) do
		c:Disconnect()
	end
	self._watchers = {}
	self._partIds = setmetatable({}, { __mode = "k" })
	self.DynamicParts = {}
	self.Targets = {}
	table.clear(self._resolveAt)
	table.clear(self._decay)
	self._bulkCount = 0
	for i = 1, #self._bulkParts do
		self._bulkParts[i] = nil
		self._bulkCFrames[i] = nil
	end
end

function ClientReplication:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	for i = 1, #self._connections do
		local conn = self._connections[i]
		if conn then conn:Disconnect() end
	end
	self._connections = {}
	self:ClearAll()
end

return ClientReplication
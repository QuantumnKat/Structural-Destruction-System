--!strict
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config            = require(script.Parent.ObjectConf).GetConfig()
local PhysicsStates     = require(ReplicatedStorage.Shared.World.Objects.PhysicsStates)
local CollideCheck      = require(script.Parent.CollideCheck)

local MAX_OBJECTS = Config.MaxInstances or 2500
local SLEEP_VELOCITY_THRESHOLD = 0.5
local SLEEP_MIN_AGE            = 3.0   
local SLEEP_CHECK_INTERVAL     = 2.0  
local MAX_ACTIVE_PARTS         = 5000 
local WAKE_RADIUS              = 24 

local ins      = table.insert
local mrandom  = math.random
local osclock  = os.clock

local ACTIVE_STATE = (PhysicsStates and PhysicsStates.Active) or "Active"
local CULLED_STATE = (PhysicsStates and PhysicsStates.Culled) or "Culled"

local ObjectManager = {}
ObjectManager.__index = ObjectManager

local inst: any = nil

local _wakeCallback: ((part: BasePart, uid: number) -> ())? = nil
local _releaseCallback: ((part: BasePart) -> ())? = nil

function ObjectManager.SetWakeCallback(fn: (part: BasePart, uid: number) -> ())
	_wakeCallback = fn
end

function ObjectManager.SetReleaseCallback(fn: (part: BasePart) -> ())
	_releaseCallback = fn
end

function ObjectManager._AddToPool(obj: Instance)
	ins(inst.Pool, obj)
	inst.PoolIndex[obj] = #inst.Pool
end

function ObjectManager._RemoveFromPool(obj: Instance)
	local idx = inst.PoolIndex[obj]
	if not idx then return end
	local last = inst.Pool[#inst.Pool]
	inst.Pool[idx] = last
	inst.PoolIndex[last] = idx
	inst.Pool[#inst.Pool] = nil
	inst.PoolIndex[obj] = nil
end

local function ClearAllJoints(obj: Instance)
	local children = obj:GetChildren()
	for i = 1, #children do
		local c = children[i]
		if c:IsA("JointInstance") or c:IsA("WeldConstraint") then
			c:Destroy()
		end
	end
end

function ObjectManager.init()
	if inst then return inst end

	inst = setmetatable({}, ObjectManager)
	inst.ActiveSet = {}
	inst.AllSet = {}
	inst.Pool = {}
	inst.PoolIndex = {}
	inst.States = {}
	inst.EventHandlers = {}
	inst.PartIds = {}
	inst.Count = 0
	inst.NextPartId = 1
	inst.ActivePartsRef = nil

	local collideCfg = Config.CollideCheck or {}
	inst.CollideCheck = CollideCheck.new(collideCfg, function(eventName, payload)
		ObjectManager.HandleEvent(eventName, payload)
	end)

	local warnedMissing = false

	inst.EventHandlers["CollideEvent"] = function(payload)
		local ok, mod = pcall(function()
			return require(script.Parent.Parent.Destruction.ServerDestructionHandler)
		end)
		if ok and mod and mod.HandleCollisionImpacts then
			local ok2, err = pcall(mod.HandleCollisionImpacts, payload)
			if not ok2 then
				warn("ObjectManager CollideEvent dispatch error: " .. tostring(err))
			end
		elseif not warnedMissing then
			warnedMissing = true
			warn("ObjectManager: ServerDestructionHandler.HandleCollisionImpacts missing — CollideEvent handler no-op")
		end
	end

	if collideCfg.Enabled ~= false and inst.CollideCheck then
		local checkInterval = collideCfg.CheckInterval or 0.1
		task.spawn(function()
			while true do
				task.wait(checkInterval)
				if inst and inst.CollideCheck then
					pcall(function()
						inst.CollideCheck:Poll()
					end)
				end
			end
		end)
	end

	if Config.AutoCleanup then
		task.spawn(function()
			local interval = Config.CleanupInterval or SLEEP_CHECK_INTERVAL
			while true do
				task.wait(interval)
				local removed, slept = ObjectManager.CleanupActiveParts()
				if removed > 0 or slept > 0 then
					print(("[ObjectManager] removed=%d slept=%d active=%d pool=%d"):format(
						removed, slept, #(inst.ActivePartsRef or {}), #inst.Pool))
				end
			end
		end)
	end

	local prewarm = Config.PrewarmCount or 0
	for _ = 1, prewarm do
		if inst.Count >= MAX_OBJECTS then break end
		local p = Instance.new("Part")
		p.Name = "Debris"
		p.Anchored = true
		p.Massless = false
		p.CanCollide = true
		p.CanQuery = true
		p.CanTouch = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		inst.Count = inst.Count + 1
		inst.PartIds[p] = inst.NextPartId
		inst.NextPartId = inst.NextPartId + 1
		inst.AllSet[p] = true
		ins(inst.Pool, p)
		inst.PoolIndex[p] = #inst.Pool
	end

	return inst
end

function ObjectManager.RegisterActiveParts(ref: { BasePart })
	inst = inst or ObjectManager.init()
	inst.ActivePartsRef = ref
end

function ObjectManager.Acquire(): BasePart?
	if not inst then ObjectManager.init() end

	local obj = table.remove(inst.Pool)
	if obj then
		inst.PoolIndex[obj] = nil
	else
		if inst.Count >= MAX_OBJECTS then
			return nil
		end
		obj = Instance.new("Part")
		obj.Name = "Debris"
		obj.TopSurface = Enum.SurfaceType.Smooth
		obj.BottomSurface = Enum.SurfaceType.Smooth
		inst.Count = inst.Count + 1
		inst.PartIds[obj] = inst.NextPartId
		inst.NextPartId = inst.NextPartId + 1
		inst.AllSet[obj] = true
	end

	ClearAllJoints(obj)

	obj.Anchored = true
	obj.Massless = false
	obj.CanCollide = true
	obj.CanQuery = true
	obj.CanTouch = true
	obj.AssemblyLinearVelocity = Vector3.zero
	obj.AssemblyAngularVelocity = Vector3.zero

	obj:SetAttribute("ObjectId", inst.PartIds[obj])

	inst.ActiveSet[obj] = true
	inst.States[obj] = ACTIVE_STATE

	return obj
end

function ObjectManager.Release(obj: Instance): boolean
	if not inst or not inst.ActiveSet[obj] then
		return false
	end
	inst.ActiveSet[obj] = nil
	inst.States[obj] = CULLED_STATE

	if _releaseCallback and obj:IsA("BasePart") then
		_releaseCallback(obj)
	end

	local ref = inst.ActivePartsRef
	if ref then
		for i = #ref, 1, -1 do
			if ref[i] == obj then
				ref[i] = ref[#ref]
				ref[#ref] = nil
			end
		end
	end

	ClearAllJoints(obj)

	obj:SetAttribute("PartIndex", nil)
	obj:SetAttribute("ObjectId", nil)
	obj:SetAttribute("_SpawnTime", nil)
	obj:SetAttribute("IsFalling", nil)
	obj:SetAttribute("HP", nil)
	obj:SetAttribute("MaterialRule", nil)
	obj:SetAttribute("IsSleeping", nil)
	obj:SetAttribute("FragmentId", nil)
	obj:SetAttribute("FragmentRoot", nil)
	obj:SetAttribute("AttackerUserId", nil)
	obj:SetAttribute("AttributionDamage", nil)   -- ⬅️ THÊM
	obj:SetAttribute("AttributionExpire", nil)

	if obj:IsA("BasePart") then
		obj.Anchored = true
		obj.AssemblyLinearVelocity = Vector3.zero
		obj.AssemblyAngularVelocity = Vector3.zero
	end
	obj.Parent = nil
	ObjectManager._AddToPool(obj)
	return true
end

function ObjectManager.ReleaseOrDestroy(obj: Instance): boolean
	if not inst then return false end

	if inst.ActiveSet[obj] then
		return ObjectManager.Release(obj)
	end

	if obj and obj.Parent then
		obj:Destroy()
	end

	inst.AllSet[obj] = nil
	inst.PartIds[obj] = nil
	inst.States[obj] = nil

	return true
end

function ObjectManager.GetPartId(obj: Instance): number?
	if not inst then return nil end
	return inst.PartIds[obj]
end

function ObjectManager.TrackCollision(obj: Instance)
	if not inst then ObjectManager.init() end
	if inst.CollideCheck then
		pcall(function()
			inst.CollideCheck:Track(obj)
		end)
	end
end

function ObjectManager.SleepPart(part: BasePart)
	if not part or not part.Parent then return end
	if part:GetAttribute("IsSleeping") then return end

	part.Anchored = true
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part:SetAttribute("IsSleeping", true)
end

function ObjectManager.WakePart(part: BasePart, attackerUserId: number?): boolean
	if not part or not part.Parent then return false end
	if not part:GetAttribute("IsSleeping") then return false end

	part.Anchored = false
	part:SetAttribute("IsSleeping", false)
	part:SetAttribute("_SpawnTime", os.clock())

	if attackerUserId then
		if _wakeCallback then
			_wakeCallback(part, attackerUserId)
		else
			part:SetAttribute("AttackerUserId", attackerUserId)
			part:SetAttribute("AttributionDamage", 0)
			part:SetAttribute("AttributionExpire", workspace:GetServerTimeNow() + 6.0)
		end
	end

	pcall(function() part:SetNetworkOwner(nil) end)
	return true
end

function ObjectManager.WakeNearby(origin: Vector3, radius: number, attackerUserId: number?): number
	if not inst then return 0 end
	local ref = inst.ActivePartsRef
	if not ref then return 0 end
	local r2 = radius * radius
	local count = 0
	for i = 1, #ref do
		local p = ref[i]
		if p and p.Parent and p:GetAttribute("IsSleeping") then
			local d = p.Position - origin
			if d:Dot(d) <= r2 then
				if ObjectManager.WakePart(p, attackerUserId) then count += 1 end
			end
		end
	end
	return count
end

function ObjectManager.GetActiveParts(): { BasePart }?
	return if inst then inst.ActivePartsRef else nil
end

function ObjectManager.CleanupActiveParts(): (number, number)
	local ref = inst.ActivePartsRef
	if not ref then return 0, 0 end

	local now       = os.clock()
	local yThresh   = Config.CleanupYThreshold or -150
	local removed   = 0
	local slept     = 0

	for i = 1, #ref do
		local p = ref[i]
		if p and p.Parent and not p:GetAttribute("IsSleeping") then
			local age = now - (p:GetAttribute("_SpawnTime") or now)
			if age > SLEEP_MIN_AGE then
				local vel = p.AssemblyLinearVelocity.Magnitude
				if vel < SLEEP_VELOCITY_THRESHOLD then
					ObjectManager.SleepPart(p)
					slept += 1
				end
			end
		end
	end

	local i = 1
	while i <= #ref do
		local p = ref[i]
		local shouldDestroy = false

		if not p or not p.Parent then
			shouldDestroy = true
		else
			local y = p.Position.Y
			if y < yThresh then
				shouldDestroy = true
				if p:GetAttribute("_DebugY") == nil then
					p:SetAttribute("_DebugY", y)
				end
			end
		end

		if shouldDestroy then
			if p and inst.ActiveSet[p] then
				ObjectManager.Release(p)
			else
				if p then p:Destroy() end
				ref[i] = ref[#ref]
				ref[#ref] = nil
			end
			removed += 1
		else
			i += 1
		end
	end

	local activeCount = 0
	for i = 1, #ref do
		if ref[i] and ref[i].Parent and not ref[i]:GetAttribute("IsSleeping") then
			activeCount += 1
		end
	end
	if activeCount > MAX_ACTIVE_PARTS then
		local toSleep = activeCount - MAX_ACTIVE_PARTS
		local slept2 = 0
		for i = 1, #ref do
			if slept2 >= toSleep then break end
			local p = ref[i]
			if p and p.Parent and not p:GetAttribute("IsSleeping") then
				ObjectManager.SleepPart(p)
				slept += 1
				slept2 += 1
			end
		end
	end

	return removed, slept
end

function ObjectManager.HandleEvent(eventName: string, payload: buffer?)
	if not inst then return end
	local h = inst.EventHandlers[eventName]
	if not h then return end
	local ok, err = pcall(h, payload)
	if not ok then
		warn(string.format("ObjectManager.HandleEvent(%s) error: %s", eventName, tostring(err)))
	end
end

function ObjectManager.RegisterEventHandler(eventName: string, handler: (buffer?) -> ())
	if not inst then ObjectManager.init() end
	inst.EventHandlers[eventName] = handler
end

return ObjectManager

--!strict
--!native

local RunService = game:GetService("RunService")

local DebrisSpawner = require(script.Parent.DebrisSpawner)
local ObjectManager = require(script.Parent.Parent.Parent.Objects.ObjectManager)
local ObjectConf: any = require(script.Parent.Parent.Parent.Objects.ObjectConf)




local CFG = {
	Enabled = true,
	LogStats = true,      

	ScanHz = 30,             
	MaxPartsPerScan = 40,   
	TimeBudgetMs = 0.6,     
	MinSpeed = 20,             
	MinImpactSpeed = 25,       
	LookAhead = 0.04,          
	MaxSegment = 40,           
	IgnoreFloors = true,       
	FloorNormalY = 0.75,       

	MaxQueue = 48,             
	MaxImpactsPerStep = 3,     
	ImpactBudgetMs = 1.5,      
	PartCooldown = 0.3,        

	MaxChainDepth = 2,         
	ForcePerMomentum = 0.15,   
	ForceMultiplier = 1.0,     
	RadiusScale = 0.6,         
	MinRadius = 1.5,
	MaxRadius = 6,
	MaxDirectBreaks = 8,       
	PropagateToFragments = false, 
	AttributionDecay = 0.5,    

	Restitution = 0.35,        
	BrokeRestitutionMul = 0.5, 
	Friction = 0.3,            
	MaxBounceSpeed = 45,
	Spin = 8,

	BreakSpeed = 40,           
	MaxBounces = 2,            
	BreakMode = "Split",       
	MaxSplits = 1,             
	MinSplitSize = 1.5,        
}




type PartState = {
	oid: any,
	depth: number,
	bounces: number,
	splits: number,
	cool: number,
	pos: Vector3?,
	t: number,
}

type Impact = {
	part: BasePart,
	st: PartState,
	hitPos: Vector3,
	normal: Vector3,
	vel: Vector3,
	speedN: number,
}

type Deps = {
	active: { BasePart },
	explode: (pos: Vector3, radius: number, force: number, opts: any) -> boolean,
	fireDebris: (list: { any }) -> (),
}

local _deps: Deps? = nil
local _conn: RBXScriptConnection? = nil
local _scheduled = false
local _lastScan = 0
local _cursor = 1
local _lastLogT = 0
local _lastLogSig = -1

local _state: { [BasePart]: PartState } = setmetatable({}, { __mode = "k" }) :: any

local _queue: { Impact } = {}
local _qHead, _qTail = 1, 0

local _params = RaycastParams.new()
_params.FilterType = Enum.RaycastFilterType.Exclude
_params.IgnoreWater = true
local _filter: { Instance } = {}

local _stats = { scanned = 0, hits = 0, processed = 0, bounced = 0, split = 0, released = 0, dropped = 0, errors = 0 }

local DebrisImpact = {}
DebrisImpact.Config = CFG

local function getState(part: BasePart): PartState
	local oid = part:GetAttribute("ObjectId")
	local st = _state[part]
	
	if not st or st.oid ~= oid then
		st = { oid = oid, depth = 0, bounces = 0, splits = 0, cool = 0, pos = nil, t = 0 }
		_state[part] = st
	end
	return st
end

local function releasePart(part: BasePart)
	_stats.released += 1
	ObjectManager.ReleaseOrDestroy(part)
end

local function withAxis(s: Vector3, axis: string, v: number): Vector3
	if axis == "X" then
		return Vector3.new(v, s.Y, s.Z)
	elseif axis == "Y" then
		return Vector3.new(s.X, v, s.Z)
	end
	return Vector3.new(s.X, s.Y, v)
end

local function axisOffset(axis: string, d: number): Vector3
	if axis == "X" then
		return Vector3.new(d, 0, 0)
	elseif axis == "Y" then
		return Vector3.new(0, d, 0)
	end
	return Vector3.new(0, 0, d)
end

local function inheritAttribution(from: BasePart, to: BasePart)
	local uid = from:GetAttribute("AttackerUserId")
	if type(uid) == "number" then
		to:SetAttribute("AttackerUserId", uid)
		to:SetAttribute("AttributionDamage", from:GetAttribute("AttributionDamage"))
		to:SetAttribute("AttributionExpire", from:GetAttribute("AttributionExpire"))
	end
end


local function trySplit(part: BasePart, st: PartState, hitPos: Vector3): boolean
	local deps = _deps
	if not deps or st.splits >= CFG.MaxSplits then return false end

	local size = part.Size
	local axis, longest = "X", size.X
	if size.Y > longest then axis, longest = "Y", size.Y end
	if size.Z > longest then axis, longest = "Z", size.Z end

	local half = longest * 0.5
	if half < CFG.MinSplitSize then return false end

	local cf = part.CFrame
	local halfSize = withAxis(size, axis, half)
	local boxes: { any } = {}
	for _, sign in { -1, 1 } do
		local boxCf = cf * CFrame.new(axisOffset(axis, sign * half * 0.5))
		table.insert(boxes, {
			Size = halfSize,
			CFrame = boxCf,
			Pos = boxCf.Position,
			Position = boxCf.Position,
			Color = part.Color,
			Material = part.Material,
		})
	end

	local camFolder = workspace:FindFirstChild("Camera")
	if not camFolder then return false end

	local matRule: any = ObjectConf.GetMaterialRule(part.Material)
	local debrisList: { any } = {}
	local spawned = DebrisSpawner.SpawnFromBoxes(boxes, part, matRule, hitPos, camFolder, deps.active, debrisList)
	if #spawned == 0 then return false end

	for i = 1, #spawned do
		local child = spawned[i]
		inheritAttribution(part, child)
		_state[child] = {
			oid = child:GetAttribute("ObjectId"),
			depth = st.depth,
			bounces = 0,
			splits = st.splits + 1,
			cool = os.clock() + CFG.PartCooldown,
			pos = nil,
			t = 0,
		}
	end
	deps.fireDebris(debrisList)

	_stats.split += 1
	releasePart(part)
	return true
end

local function processImpact(imp: Impact)
	local deps = _deps
	local part = imp.part
	if not deps or not part.Parent then return end

	local st = imp.st
	local mass = part.AssemblyMass
	local broke = false

	
	if st.depth < CFG.MaxChainDepth then
		local radius = math.clamp(part.Size.Magnitude * CFG.RadiusScale, CFG.MinRadius, CFG.MaxRadius)
		local force = mass * imp.speedN * CFG.ForcePerMomentum

		local uid = part:GetAttribute("AttackerUserId")
		local expire = part:GetAttribute("AttributionExpire")
		if type(expire) == "number" and workspace:GetServerTimeNow() > expire then
			uid = nil
		end
		local srcDmg = part:GetAttribute("AttributionDamage")
		local attrDmg = if type(srcDmg) == "number" then srcDmg * CFG.AttributionDecay else force

		local exclude: { [number]: boolean } = {}
		local selfIdx = part:GetAttribute("PartIndex")
		if type(selfIdx) == "number" then exclude[selfIdx] = true end
		local oid = part:GetAttribute("ObjectId")

		local before = #deps.active
		deps.explode(imp.hitPos, radius, force, {
			ExcludeIdx = exclude,
			ExcludeIds = if type(oid) == "number" then { [oid] = true } else nil,
			ExcludeFragmentId = part:GetAttribute("FragmentId"),
			AttackerUserId = if type(uid) == "number" then uid else nil,
			AttributionDamage = attrDmg,
			ForceMultiplier = CFG.ForceMultiplier,
			MaxDirectBreaks = CFG.MaxDirectBreaks,
			HitDebris = CFG.PropagateToFragments,
			NoShockwave = true,
		})

		local after = #deps.active
		if after > before then
			broke = true
			for i = before + 1, after do
				local p = deps.active[i]
				if p and p ~= part then
					_state[p] = {
						oid = p:GetAttribute("ObjectId"),
						depth = st.depth + 1,
						bounces = 0,
						splits = 0,
						cool = os.clock() + CFG.PartCooldown,
						pos = nil,
						t = 0,
					}
				end
			end
		end
	end

	if not part.Parent then return end

	st.bounces += 1
	st.cool = os.clock() + CFG.PartCooldown

	local shouldBreak = CFG.BreakMode ~= "None"
		and (imp.speedN >= CFG.BreakSpeed or st.bounces >= CFG.MaxBounces)

	if shouldBreak then
		if CFG.BreakMode == "Split" and trySplit(part, st, imp.hitPos) then
			return
		end
		releasePart(part)
		return
	end

	local n = imp.normal
	local vn = imp.vel:Dot(n)
	local vt = imp.vel - n * vn
	local e = CFG.Restitution * (if broke then CFG.BrokeRestitutionMul else 1)
	local out = vt * (1 - CFG.Friction) - n * vn * e
	local sp = out.Magnitude
	if sp > CFG.MaxBounceSpeed then
		out = out * (CFG.MaxBounceSpeed / sp)
	end

	part.Anchored = false
	part:ApplyImpulse(out * part.AssemblyMass)
	part.AssemblyAngularVelocity = Vector3.new(
		math.random() - 0.5, math.random() - 0.5, math.random() - 0.5
	) * CFG.Spin
	_stats.bounced += 1
end

local function drainQueue()
	local t0 = os.clock()
	local budget = CFG.ImpactBudgetMs / 1000
	local done = 0

	while _qHead <= _qTail and done < CFG.MaxImpactsPerStep do
		if done > 0 and (os.clock() - t0) >= budget then break end

		local imp = _queue[_qHead]
		_queue[_qHead] = nil
		_qHead += 1
		done += 1

		local ok, err = pcall(processImpact, imp)
		if not ok then
			_stats.errors += 1
			warn("[DebrisImpact] processImpact error: " .. tostring(err))
			if imp.part.Parent then
				imp.part.Anchored = false
			end
		end
		_stats.processed += 1
	end

	if _qHead > _qTail then
		_qHead, _qTail = 1, 0
	end
end

local function probe(part: BasePart, now: number)
	local st = getState(part)
	local pos = part.Position
	local prevPos, prevT = st.pos, st.t
	st.pos, st.t = pos, now

	local vel = part.AssemblyLinearVelocity
	local speed = vel.Magnitude
	if speed < CFG.MinSpeed or now < st.cool then return end

	local from = if prevPos and (now - prevT) < 0.5 then prevPos else pos - vel * 0.03
	local seg = (pos + vel * CFG.LookAhead) - from
	local len = seg.Magnitude
	if len < 0.05 then return end
	if len > CFG.MaxSegment then
		seg = seg.Unit * CFG.MaxSegment
	end

	local radius = math.clamp(part.Size.Magnitude * 0.2, 0.3, 1.5)
	_filter[1] = part
	_params.FilterDescendantsInstances = _filter

	local hit = workspace:Spherecast(from, radius, seg, _params)
	if not hit then return end

	local inst = hit.Instance
	if not inst.Anchored then return end
	if inst:GetAttribute("IsSleeping") or type(inst:GetAttribute("ObjectId")) == "number" then return end

	local n = hit.Normal
	if CFG.IgnoreFloors and n.Y > CFG.FloorNormalY then return end

	local speedN = -vel:Dot(n)
	if speedN < CFG.MinImpactSpeed then return end

	_stats.hits += 1

	if (_qTail - _qHead + 1) >= CFG.MaxQueue then
		_stats.dropped += 1
		releasePart(part)
		return
	end

	local cf = part.CFrame
	local size = part.Size
	local halfExtent = 0.5 * (
		math.abs(n:Dot(cf.RightVector)) * size.X
			+ math.abs(n:Dot(cf.UpVector)) * size.Y
			+ math.abs(n:Dot(cf.LookVector)) * size.Z
	)
	local center = hit.Position + n * (halfExtent + 0.05)

	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	part.CFrame = CFrame.new(center) * (cf - cf.Position)
	part.Anchored = true

	_qTail += 1
	_queue[_qTail] = { part = part, st = st, hitPos = hit.Position, normal = n, vel = vel, speedN = speedN }
end

local function scan(now: number)
	local deps = _deps
	if not deps then return end
	local active = deps.active
	if not active then return end
	local count = #active
	if count == 0 then return end

	local budgetSec = CFG.TimeBudgetMs / 1000
	local t0 = os.clock()

	for _ = 1, math.min(count, CFG.MaxPartsPerScan) do
		if (os.clock() - t0) >= budgetSec then break end
		if _cursor > count then _cursor = 1 end

		local part = active[_cursor]
		_cursor += 1

		if part
			and part.Parent
			and not part.Anchored
			and type(part:GetAttribute("ObjectId")) == "number"
			and not part:GetAttribute("IsSleeping")
		then
			_stats.scanned += 1
			probe(part, now)
		end
	end
end

local function step()
	if not CFG.Enabled then return end
	local now = os.clock()

	if (now - _lastScan) >= (1 / CFG.ScanHz) then
		_lastScan = now
		scan(now)
	end

	if _qHead <= _qTail then
		drainQueue()
	end

	if CFG.LogStats and (now - _lastLogT) >= 5 then
		_lastLogT = now
		local sig = _stats.scanned + _stats.hits + _stats.processed
		if sig ~= _lastLogSig then
			_lastLogSig = sig
			local deps = _deps
			print(("[DebrisImpact] active=%d scanned=%d hits=%d processed=%d bounced=%d split=%d released=%d dropped=%d errors=%d queue=%d"):format(
				if deps then #deps.active else 0,
				_stats.scanned, _stats.hits, _stats.processed, _stats.bounced,
				_stats.split, _stats.released, _stats.dropped, _stats.errors,
				_qTail - _qHead + 1
				))
		end
	end
end

function DebrisImpact.Init(deps: Deps)
	if type(deps) ~= "table" or type(deps.active) ~= "table" then
		warn("[DebrisImpact] Init bị bỏ qua: deps.active là nil (SetContext chưa có ActiveParts)")
		return
	end
	_deps = deps
	_cursor = 1
	print(("[DebrisImpact] Init ok, active=%d"):format(#deps.active))
	if _conn then return end

	_conn = RunService.Heartbeat:Connect(function()
		if _scheduled then return end
		_scheduled = true
		task.defer(function()
			_scheduled = false
			step()
		end)
	end)
end

function DebrisImpact.Stats(): { [string]: number }
	local s = table.clone(_stats)
	s.queue = _qTail - _qHead + 1
	return s
end

return DebrisImpact
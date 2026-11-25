--!strict
--!native

--
--

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local Conf: any       = require(script.Parent.Parent.Fragments.FragmentConf)
local HitShapeMod     = require(script.Parent.Parent.Geometry.HitShape)
local ObjectManager   = require(script.Parent.Parent.Parent.Objects.ObjectManager)

local mathmax, mathmin = math.max, math.min
local random = math.random
local osclock = os.clock

local Thrust = {}
local T: any = Conf.Thrust

local S: any = {
	inited = false, active = nil, event = nil,
	entries = {}, cursor = 0,
	stats = { launched = 0, shock = 0, players = 0, applied = 0, overflow = 0 },
}

local function wake(part: BasePart)
	if part:GetAttribute("IsSleeping") then
		local conn = part:GetConnectedParts(true)
		for i = 1, #conn do
			ObjectManager.WakePart(conn[i])
		end
		ObjectManager.WakePart(part)
	end
end

local function randVec(): Vector3
	return Vector3.new(random() - 0.5, random() - 0.5, random() - 0.5)
end

local function applyChanges(items: { any })
	local groups: { [BasePart]: any } = {}
	local order: { BasePart } = {}

	for i = 1, #items do
		local part: BasePart = items[i].part
		if part.Parent == nil then continue end
		local root: BasePart = part.AssemblyRootPart or part

		local g = groups[root]
		if not g then
			g = { P = Vector3.zero, L = Vector3.zero, com = root.AssemblyCenterOfMass }
			groups[root] = g
			order[#order + 1] = root
		end
		local m = mathmax(part:GetMass(), 1e-3)
		local p: Vector3 = (items[i].dv :: Vector3) * m
		g.P += p
		g.L += (part.Position - g.com):Cross(p)
	end

	local now = osclock()
	local sustained = T.Mode == "Sustained"
	for i = 1, #order do
		local root = order[i]
		local g = groups[root]
		if root.Anchored then continue end

		root.AssemblyAngularVelocity += randVec() * T.Spin

		if sustained and #S.entries < T.MaxActive then
			S.entries[#S.entries + 1] = {
				root = root, J = g.P, L = g.L, t0 = now, T = mathmax(T.Duration, 0.02),
				p = T.DecayPower, prev = 0,
				oid = root:GetAttribute("ObjectId"),
				M = root.AssemblyMass,
			}
		else
			if sustained then S.stats.overflow += 1 end
			root:ApplyImpulse(g.P)
			root:ApplyAngularImpulse(g.L)
		end
	end
end

------------------------------------------------------------------
-- PUBLIC
------------------------------------------------------------------
function Thrust.Launch(parts: { BasePart }, info: any): number
	if not S.inited or T.Enabled == false or #parts < T.MinParts or #parts == 0 then return 0 end

	local center: Vector3 = info.Center
	local force: number = info.Force
	local shape: any = info.Shape

	local items: { any } = {}
	for i = 1, #parts do
		items[i] = { ref = parts[i], pos = parts[i].Position, half = parts[i].Size * 0.5 }
	end

	local qmap: { [BasePart]: any } = {}
	local reach = 0
	if shape then
		reach = HitShapeMod.BoundingRadius(shape)
		for _, h in ipairs(HitShapeMod.QueryParts(shape, items, force)) do
			qmap[h.ref] = h
		end
	end

	local list: { any } = {}
	for i = 1, #parts do
		local p = parts[i]
		wake(p)

		local f: number
		local dir: Vector3
		local h = qmap[p]
		if h then
			f, dir = h.force, h.dir
		else
			local d: Vector3 = p.Position - center
			local dist = d.Magnitude
			dir = if dist > 1e-3 then d / dist else Vector3.yAxis
			f = if reach > 0
				then force * 0.25 * (reach / mathmax(dist, reach)) ^ 2
				else force * 0.25 / (1 + dist * 0.1)
		end

		local v: Vector3 = dir + Vector3.yAxis * T.UpBias + randVec() * T.Jitter
		if v.Magnitude > 1e-3 then v = v.Unit end

		local m = mathmax(p:GetMass(), 1e-3)
		local dv = mathmin(T.MaxSpeed, f / (m ^ T.MassExponent) * T.SpeedPerForce)
		list[#list + 1] = { part = p, dv = v * dv }
	end

	applyChanges(list)
	S.stats.launched += #list
	return #list
end

local function knockPlayers(shape: any, force: number, center: Vector3, reach: number): number
	local P = T.Players
	local ev: RemoteEvent? = S.event
	if not ev then return 0 end
	local count = 0

	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local d: Vector3 = root.Position - center
			if d:Dot(d) <= (reach + 3) * (reach + 3) then
				local hits = HitShapeMod.QueryParts(shape, {
					{ ref = root, pos = root.Position, half = Vector3.new(1, 2.5, 0.5) },
				}, force)
				local h = hits[1]
				if h then
					local dv = mathmin(P.MaxSpeed, h.force * P.SpeedPerForce)
					local v: Vector3 = (h.dir :: Vector3) * dv + Vector3.yAxis * (P.UpBoost * (h.t :: number))
					ev:FireClient(plr, "KNOCKBACK", v)
					count += 1
				end
			end
		end
	end
	S.stats.players += count
	return count
end

function Thrust.Shockwave(shape: any, force: number, opts: any?): number
	local W = T.Shockwave
	if not S.inited or T.Enabled == false or W.Enabled == false then return 0 end
	local exclude: { [BasePart]: boolean }? = if opts then opts.Exclude else nil

	local center: Vector3 = shape.CFrame.Position
	local R = HitShapeMod.BoundingRadius(shape) * W.RadiusScale
	local n = 0

	if W.AffectDebris then
		local active: { BasePart } = S.active
		local parts: { BasePart } = {}
		for i = 1, #active do
			local p = active[i]
			if p and p.Parent and not (exclude and exclude[p]) then
				local reach = R + p.Size.Magnitude * 0.5
				local d: Vector3 = p.Position - center
				if d:Dot(d) <= reach * reach then
					parts[#parts + 1] = p
				end
			end
		end
		if #parts > 0 then
			n += Thrust.Launch(parts, { Center = center, Force = force * W.Scale, Shape = shape })
			S.stats.shock += #parts
		end
	end

	if T.Players.Enabled then
		n += knockPlayers(shape, force, center, R)
	end
	return n
end

function Thrust.Apply(idxs: { number }, partMap: { [number]: BasePart }, info: any): number
	if not S.inited or T.Enabled == false then return 0 end

	local parts: { BasePart } = {}
	local set: { [BasePart]: boolean } = {}
	for i = 1, #idxs do
		local p = partMap[idxs[i]]
		if p and p.Parent and not p.Anchored and not set[p] then
			set[p] = true
			parts[#parts + 1] = p
		end
	end

	local shape: any = info.Shape
	if not shape then
		shape = { Type = "Sphere", CFrame = CFrame.new(info.Center), Radius = info.Radius or 12, Falloff = "Smooth" }
	end

	local n = 0
	if #parts > 0 then
		n += Thrust.Launch(parts, { Center = info.Center, Force = info.Force * T.LaunchScale, Shape = shape })
	end
	if not info.NoShockwave then
		n += Thrust.Shockwave(shape, info.Force, { Exclude = set })
	end
	return n
end

function Thrust.Step(_dt: number)
	local entries: { any } = S.entries
	local n = #entries
	if n == 0 then return end

	local now = osclock()
	local cursor: number = S.cursor
	for _ = 1, mathmin(n, T.MaxPerStep) do
		if n == 0 then break end
		cursor = cursor % n + 1
		local e = entries[cursor]
		local root: BasePart = e.root
		local remove = false

		local stale = root.Parent == nil
			or root.Anchored
			or root:GetAttribute("IsSleeping") == true
			or root:GetAttribute("ObjectId") ~= e.oid
			or math.abs(root.AssemblyMass - e.M) > e.M * 0.25

		if stale then
			remove = true
		else
			local s = (now - e.t0) / e.T
			if s >= 1 then
				s = 1
				remove = true
			end
			local cum = 1 - (1 - s) ^ (e.p + 1)
			local frac = cum - e.prev
			if frac > 0 then
				e.prev = cum
				root:ApplyImpulse((e.J :: Vector3) * frac)
				root:ApplyAngularImpulse((e.L :: Vector3) * frac)
				local v = root.AssemblyLinearVelocity
				local mag = v.Magnitude
				if mag > T.MaxSpeed then
					root.AssemblyLinearVelocity = v * (T.MaxSpeed / mag)
				end
				local w = root.AssemblyAngularVelocity
				local wm = w.Magnitude
				if wm > T.MaxSpin then
					root.AssemblyAngularVelocity = w * (T.MaxSpin / wm)
				end
				S.stats.applied += 1
			end
		end

		if remove then
			entries[cursor] = entries[n]
			entries[n] = nil
			n -= 1
			cursor -= 1
		end
	end
	S.cursor = cursor
end

function Thrust.Cancel(part: BasePart)
	local root = part.AssemblyRootPart or part
	local entries: { any } = S.entries
	for i = #entries, 1, -1 do
		if entries[i].root == root then
			entries[i] = entries[#entries]
			entries[#entries] = nil
		end
	end
end

function Thrust.Init(ActiveParts: { BasePart }, replicationEvent: RemoteEvent?)
	if S.inited or T.Enabled == false then return end
	S.inited = true
	S.active = ActiveParts
	S.event = replicationEvent
	RunService.Heartbeat:Connect(Thrust.Step)
end

function Thrust.Stats(): { [string]: number }
	local s = S.stats
	return {
		Entries = #S.entries, Launched = s.launched, Shockwave = s.shock,
		Players = s.players, Applied = s.applied, Overflow = s.overflow,
	}
end

return Thrust

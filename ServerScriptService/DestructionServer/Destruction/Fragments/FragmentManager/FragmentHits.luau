--!strict
-- EditorSync: refactor-v1
--!native
return function(deps: any)
local S, Conf = deps.State, deps.Config
local ObjectManager, PartIds, HitShapeMod = deps.ObjectManager, deps.PartIds, deps.HitShape
local hpOf, wakeAssembly, removeVoxel = deps.HpOf, deps.WakeAssembly, deps.RemoveVoxel
local ins, osclock = table.insert, os.clock
local mathmax, mathmin, mathclamp, random = math.max, math.min, math.clamp, math.random
local FragmentManager = {}
local function splitPart(part: BasePart, force: number, point: Vector3, full: boolean, hp: number): number
	local D = Conf.Debris
	local active: { BasePart } = S.active
	local size = part.Size
	local cf = part.CFrame
	local lp = cf:PointToObjectSpace(point)
	local comps = { size.X, size.Y, size.Z }
	local lpc = { lp.X, lp.Y, lp.Z }
	local vol = size.X * size.Y * size.Z

	local axes: { number }
	if full then
		axes = { 1, 2, 3 }
	else
		local best = 1
		for a = 2, 3 do
			if comps[a] > comps[best] then best = a end
		end
		axes = { best }
	end

	local nAxes = #axes
	local ranges: { any } = {}
	for k = 1, nAxes do
		local s = comps[axes[k]]
		local t = mathclamp((lpc[axes[k]] + s * 0.5) / s, 0.3, 0.7)
		local s0, s1 = s * t, s * (1 - t)
		ranges[k] = { { -s * 0.5 + s0 * 0.5, s0 }, { -s * 0.5 + s0 + s1 * 0.5, s1 } }
	end

	local mass = mathmax(part:GetMass(), 1e-3)
	local speed = mathmin(D.MaxPieceSpeed, force / mass * D.PieceSpeed)
	local baseVel = part.AssemblyLinearVelocity
	local fid = part:GetAttribute("FragmentId")
	local parent = part.Parent
	local created = 0

	for m = 0, 2 ^ nAxes - 1 do
		local c = { 0, 0, 0 }
		local sz = { size.X, size.Y, size.Z }
		for k = 1, nAxes do
			local r = ranges[k][bit32.band(bit32.rshift(m, k - 1), 1) + 1]
			c[axes[k]] = r[1]
			sz[axes[k]] = r[2]
		end
		local pv = sz[1] * sz[2] * sz[3]
		local ext = mathmax(sz[1], sz[2], sz[3])
		if pv >= D.MinPieceVolume and ext >= D.MinPieceExtent then
			local piece = ObjectManager.Acquire()
			if piece then
				piece.Size = Vector3.new(sz[1], sz[2], sz[3])
				piece.CFrame = cf * CFrame.new(c[1], c[2], c[3])
				piece.Color = part.Color
				piece.Material = part.Material
				piece.Transparency = part.Transparency
				piece.Reflectance = part.Reflectance
				piece.CanCollide = true
				piece.Massless = false
				piece.Anchored = false

				piece:SetAttribute("IsFalling", true)
				piece:SetAttribute("IsSleeping", false)
				piece:SetAttribute("_SpawnTime", osclock())
				piece:SetAttribute("HP", hp * (pv / vol) ^ (1 / 3))
				if fid ~= nil then piece:SetAttribute("FragmentId", fid) end
				piece:SetAttribute("ObjectId", PartIds.NewDebrisId())
				piece.Parent = parent
				PartIds.Announce(piece, true)
				pcall(function() piece:SetNetworkOwner(nil) end)

				local d: Vector3 = piece.Position - point
				local dirP = if d.Magnitude > 1e-3 then d.Unit else cf.UpVector
				piece.AssemblyLinearVelocity = baseVel + dirP * speed
				piece.AssemblyAngularVelocity = Vector3.new(random() - 0.5, random() - 0.5, random() - 0.5) * 6
				ins(active, piece)
				if D.TrackCollisions then ObjectManager.TrackCollision(piece) end
				created += 1
			end
		end
	end

	if S.log then
		local id = part:GetAttribute("ObjectId")
		if type(id) == "number" then S.log:Split(id, created) end
	end
	return created
end

function FragmentManager.HitFragments(shape: any, force: number, opts: any?): number
	if not S.inited or Conf.Debris.HitEnabled == false then return 0 end
	local o: any = opts or {}
	local D = Conf.Debris
	local active: { BasePart } = S.active

	local center: Vector3 = shape.CFrame.Position
	local R = HitShapeMod.BoundingRadius(shape)
	local excludeIds: any = o.ExcludeIds
	local excludeFid = o.ExcludeFragmentId

	local items: { any } = {}
	for i = 1, #active do
		local p = active[i]
		if p and p.Parent then
			local half = p.Size * 0.5
			local pos = p.Position
			local reach = R + half.Magnitude
			local d = pos - center
			if d:Dot(d) <= reach * reach then
				local skip = false
				if excludeIds and excludeIds[p:GetAttribute("ObjectId")] then skip = true end
				if not skip and excludeFid ~= nil and p:GetAttribute("FragmentId") == excludeFid then skip = true end
				if not skip then
					items[#items + 1] = { ref = p, pos = pos, half = half }
				end
			end
		end
	end
	if #items == 0 then return 0 end

	local hits = HitShapeMod.QueryParts(shape, items, force)
	local affected = 0
	local splits = 0

	for i = 1, #hits do
		local h = hits[i]
		local part: BasePart = h.ref
		if not part.Parent then continue end

		local f: number = h.force
		local hp = hpOf(part)
		wakeAssembly(part)

		if f >= hp * D.SplitForceRatio and splits < D.MaxSplitsPerHit then
			local full = f >= hp * D.FullShatterRatio
			splitPart(part, f, h.point, full, hp)
			removeVoxel(part, false)
			splits += 1
			affected += 1
		elseif f >= hp * 0.1 then
			local mass = mathmax(part:GetMass(), 1e-3)
			local sp = mathmin(D.MaxPieceSpeed, f / mass * D.PieceSpeed)
			part.AssemblyLinearVelocity += (h.dir :: Vector3) * sp
			affected += 1
		end
	end
	return affected
end

return FragmentManager.HitFragments
end

--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NeighborConf = require(ReplicatedStorage.Shared.Destruction.NeighborConf)

local NeighborTracker = {}
local ATTR = "Neighbors"

function NeighborTracker.GetNeighbors(part: BasePart): {number}
	local s = part:GetAttribute(ATTR)
	if type(s) ~= "string" or #s == 0 then return {} end
	local buf = buffer.fromstring(s)
	local n = buffer.len(buf) // 2
	local out = table.create(n)
	for i = 0, n - 1 do
		out[i + 1] = buffer.readu16(buf, i * 2)
	end
	return out
end

function NeighborTracker.SetNeighbors(part: BasePart, neighbors: {number})
	local n = #neighbors
	if n == 0 then
		part:SetAttribute(ATTR, "")
		return
	end
	local buf = buffer.create(n * 2)
	for i, id in ipairs(neighbors) do
		buffer.writeu16(buf, (i - 1) * 2, id)
	end
	part:SetAttribute(ATTR, buffer.tostring(buf))
end

function NeighborTracker.AddNeighbor(part: BasePart, id: number)
	local list = NeighborTracker.GetNeighbors(part)
	for _, v in ipairs(list) do
		if v == id then return end
	end
	table.insert(list, id)
	NeighborTracker.SetNeighbors(part, list)
end

function NeighborTracker.RemoveNeighbor(part: BasePart, id: number)
	local list = NeighborTracker.GetNeighbors(part)
	local found = false
	for i = #list, 1, -1 do
		if list[i] == id then
			table.remove(list, i)
			found = true
		end
	end
	if found then
		NeighborTracker.SetNeighbors(part, list)
	end
end

local function getAABB(p: BasePart): (Vector3, Vector3)
	local cf, sz = p.CFrame, p.Size
	local h = sz * 0.5
	local corners = {
		cf * Vector3.new(-h.X, -h.Y, -h.Z),
		cf * Vector3.new( h.X, -h.Y, -h.Z),
		cf * Vector3.new(-h.X,  h.Y, -h.Z),
		cf * Vector3.new( h.X,  h.Y, -h.Z),
		cf * Vector3.new(-h.X, -h.Y,  h.Z),
		cf * Vector3.new( h.X, -h.Y,  h.Z),
		cf * Vector3.new(-h.X,  h.Y,  h.Z),
		cf * Vector3.new( h.X,  h.Y,  h.Z),
	}
	local min, max = corners[1], corners[1]
	for i = 2, 8 do
		local c = corners[i]
		min = Vector3.new(math.min(min.X, c.X), math.min(min.Y, c.Y), math.min(min.Z, c.Z))
		max = Vector3.new(math.max(max.X, c.X), math.max(max.Y, c.Y), math.max(max.Z, c.Z))
	end
	return min, max
end

local function aabbOverlap(minA: Vector3, maxA: Vector3, minB: Vector3, maxB: Vector3, gap: number): boolean
	return minA.X - gap <= maxB.X and maxA.X + gap >= minB.X
		and minA.Y - gap <= maxB.Y and maxA.Y + gap >= minB.Y
		and minA.Z - gap <= maxB.Z and maxA.Z + gap >= minB.Z
end

function NeighborTracker.BuildFromProximity(parts: { BasePart }, gap: number?, cellSize: number?)
	local conf = NeighborConf.Get()
	gap      = gap      or conf.Gap
	cellSize = cellSize or conf.CellSize

	local aabbs: { [BasePart]: {Vector3} } = {}
	local grid:  { [string]: { BasePart } } = {}

	for _, p in ipairs(parts) do
		local mn, mx = getAABB(p)
		aabbs[p] = { mn, mx }

		local minX, maxX = math.floor(mn.X / cellSize), math.floor(mx.X / cellSize)
		local minY, maxY = math.floor(mn.Y / cellSize), math.floor(mx.Y / cellSize)
		local minZ, maxZ = math.floor(mn.Z / cellSize), math.floor(mx.Z / cellSize)

		for x = minX, maxX do
			for y = minY, maxY do
				for z = minZ, maxZ do
					local key = x .. "_" .. y .. "_" .. z
					local bucket = grid[key]
					if not bucket then bucket = {}; grid[key] = bucket end
					table.insert(bucket, p)
				end
			end
		end
	end

	local acc: { [number]: {[number]: boolean} } = {}
	local listAcc: { [number]: {number} } = {}

	for _, p in ipairs(parts) do
		local idxA = p:GetAttribute("PartIndex")
		if not idxA then continue end
		local mnA, mxA = aabbs[p][1], aabbs[p][2]

		local minX, maxX = math.floor(mnA.X / cellSize), math.floor(mxA.X / cellSize)
		local minY, maxY = math.floor(mnA.Y / cellSize), math.floor(mxA.Y / cellSize)
		local minZ, maxZ = math.floor(mnA.Z / cellSize), math.floor(mxA.Z / cellSize)

		for x = minX, maxX do
			for y = minY, maxY do
				for z = minZ, maxZ do
					local bucket = grid[x .. "_" .. y .. "_" .. z]
					if bucket then
						for _, q in ipairs(bucket) do
							if q ~= p then
								local idxB = q:GetAttribute("PartIndex")
								if idxB and idxA < idxB then
									local mnB, mxB = aabbs[q][1], aabbs[q][2]
									if aabbOverlap(mnA, mxA, mnB, mxB, gap) then
										acc[idxA] = acc[idxA] or {}
										if not acc[idxA][idxB] then
											acc[idxA][idxB] = true
											listAcc[idxA] = listAcc[idxA] or {}
											table.insert(listAcc[idxA], idxB)
										end

										acc[idxB] = acc[idxB] or {}
										if not acc[idxB][idxA] then
											acc[idxB][idxA] = true
											listAcc[idxB] = listAcc[idxB] or {}
											table.insert(listAcc[idxB], idxA)
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end

	for _, p in ipairs(parts) do
		local idx = p:GetAttribute("PartIndex")
		if idx then
			NeighborTracker.SetNeighbors(p, listAcc[idx] or {})
		end
	end
end

return NeighborTracker

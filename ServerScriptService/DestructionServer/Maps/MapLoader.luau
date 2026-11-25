--!strict
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NeighborTracker   = require(ReplicatedStorage.Shared.Destruction.NeighborTracker)
local MapLoaderConfig   = require(ReplicatedStorage.Shared.Map.MapLoaderConfig)

local CFG  = MapLoaderConfig
local DEF  = CFG.DEFAULT
local ins  = table.insert
local typeOf = typeof
local mathmax = math.max
local mathsqrt = math.sqrt

local MapLoader = {}

local function getNumAttr(part: BasePart, name: string): number
	local v = part:GetAttribute(name)
	if typeOf(v) == "number" then return v end
	return DEF[name] or 1
end

local function getStrAttr(part: BasePart, name: string, default: string): string
	local v = part:GetAttribute(name)
	if typeOf(v) == "string" then return v end
	return default
end

local function getBoolAttr(part: BasePart, name: string, default: boolean): boolean
	local v = part:GetAttribute(name)
	if typeOf(v) == "boolean" then return v end
	return default
end

local function assignDeterministicIndex(parts: { BasePart })
	if not parts or #parts == 0 then return end

	local yieldN = CFG.INDEX_BATCH_YIELD or 200
	local idxStart = CFG.INDEX_START or 1
	local idxMax = CFG.INDEX_MAX or 4_000_000_000

	table.sort(parts, function(a, b)
		local pa, pb = a.Position, b.Position
		if pa.X ~= pb.X then return pa.X < pb.X end
		if pa.Y ~= pb.Y then return pa.Y < pb.Y end
		if pa.Z ~= pb.Z then return pa.Z < pb.Z end
		local sa, sb = a.Size, b.Size
		if sa.X ~= sb.X then return sa.X < sb.X end
		if sa.Y ~= sb.Y then return sa.Y < sb.Y end
		if sa.Z ~= sb.Z then return sa.Z < sb.Z end
		return a.Name < b.Name
	end)

	local used: { [number]: boolean } = {}
	local preAssigned: { [BasePart]: number } = {}

	for i = 1, #parts do
		local p = parts[i]
		local v = p:GetAttribute("PartIndex")
		if typeOf(v) == "number" and v >= idxStart and v <= idxMax then
			if used[v] then
				warn(string.format(
					"MapLoader: PartIndex collision %d on %s — reassigning",
					v, p:GetFullName()
					))
			else
				used[v] = true
				preAssigned[p] = v
			end
		end
	end

	local nextIdx = idxStart
	for i = 1, #parts do
		local p = parts[i]
		local assigned = preAssigned[p]
		if not assigned then
			while used[nextIdx] do
				nextIdx = nextIdx + 1
				if nextIdx > idxMax then
					error("MapLoader: PartIndex overflow > INDEX_MAX")
				end
			end
			used[nextIdx] = true
			assigned = nextIdx
			preAssigned[p] = assigned
			nextIdx = nextIdx + 1
		end
		p:SetAttribute("PartIndex", assigned)
		if i % yieldN == 0 then
			task.wait()
		end
	end
end

local function detectDestructible(part: BasePart, mapFolder: Instance): boolean
	local attr = part:GetAttribute("IsDestructible")
	if typeOf(attr) == "boolean" then
		return attr
	end

	local current = part.Parent
	while current and current ~= mapFolder do
		local name = current.Name
		if CFG.UNBREAKABLE_FOLDERS[name] then return false end
		if CFG.BREAKABLE_FOLDERS[name] then return true end
		current = current.Parent
	end
	return true
end

local function detectAnchor(part: BasePart, mapFolder: Instance): boolean
	local attr = part:GetAttribute("IsAnchor")
	if typeOf(attr) == "boolean" then
		return attr
	end

	local current = part.Parent
	while current and current ~= mapFolder do
		if CFG.UNBREAKABLE_FOLDERS[current.Name] then
			return true
		end
		current = current.Parent
	end
	return false
end

local function aabbGap(a: BasePart, b: BasePart): number
	local aHalf = a.Size * 0.5
	local bHalf = b.Size * 0.5
	local aPos, bPos = a.Position, b.Position

	local aMinX, aMaxX = aPos.X - aHalf.X, aPos.X + aHalf.X
	local aMinY, aMaxY = aPos.Y - aHalf.Y, aPos.Y + aHalf.Y
	local aMinZ, aMaxZ = aPos.Z - aHalf.Z, aPos.Z + aHalf.Z
	local bMinX, bMaxX = bPos.X - bHalf.X, bPos.X + bHalf.X
	local bMinY, bMaxY = bPos.Y - bHalf.Y, bPos.Y + bHalf.Y
	local bMinZ, bMaxZ = bPos.Z - bHalf.Z, bPos.Z + bHalf.Z

	local dx = mathmax(0, mathmax(aMinX - bMaxX, bMinX - aMaxX))
	local dy = mathmax(0, mathmax(aMinY - bMaxY, bMinY - aMaxY))
	local dz = mathmax(0, mathmax(aMinZ - bMaxZ, bMinZ - aMaxZ))

	return mathsqrt(dx * dx + dy * dy + dz * dz)
end

local function readPartData(part: BasePart, mapFolder: Instance, partIdx: number): any
	local isAnchor = detectAnchor(part, mapFolder)
	local isDestructible = detectDestructible(part, mapFolder)

	return {
		Name = part.Name,
		CFrame = part.CFrame,
		Size = part.Size,
		Color = part.Color,
		Material = part.Material.Value,
		PartIndex = partIdx,

		Mass = getNumAttr(part, "Mass"),
		HP = getNumAttr(part, "HP"),
		Hardness = getNumAttr(part, "Hardness"),
		ForceTransmission = getNumAttr(part, "ForceTransmission"),
		StressResistance = getNumAttr(part, "StressResistance"),
		TensileStrength = getNumAttr(part, "TensileStrength"),
		BendingForce = getNumAttr(part, "BendingForce"),
		CompressionStrength = getNumAttr(part, "CompressionStrength"),
		Pressure = getNumAttr(part, "Pressure"),

		IsAnchor = isAnchor,
		IsDestructible = isDestructible,

		OnDisconnect = getStrAttr(part, "OnDisconnect", DEF.OnDisconnect),
		BreakRadius = getNumAttr(part, "BreakRadius"),
		ShatterAirPercent = getNumAttr(part, "ShatterAirPercent"),
		MaxDebrisPerPart = getNumAttr(part, "MaxDebrisPerPart"),
		UnweldPercentage = getNumAttr(part, "UnweldPercentage"),

		Category = isAnchor and 3 or 1,
	}
end

function MapLoader.LoadMapAsChunks(mapFolder: Instance, batchSize: number?): any
	if not mapFolder then
		return { Parts = {}, Welds = {} }
	end

	local yieldN = batchSize or CFG.LOAD_BATCH_SIZE or 200

	local allParts: { BasePart } = {}
	local descendants = mapFolder:GetDescendants()
	for i = 1, #descendants do
		local d = descendants[i]
		if d:IsA("BasePart") then
			ins(allParts, d)
		end
	end

	assignDeterministicIndex(allParts)

	for i = 1, #allParts do
		local part = allParts[i]
		local children = part:GetChildren()
		for j = 1, #children do
			local c = children[j]
			if c:IsA("WeldConstraint") or c:IsA("Weld") then
				local p0, p1 = c.Part0, c.Part1
				if p0 and p1 then
					local f0 = p0:GetAttribute("IsFalling") == true
					local f1 = p1:GetAttribute("IsFalling") == true
					if f0 ~= f1 then
						c:Destroy()
					end
				end
			end
		end
	end

	local partDataMap: { [number]: any } = {}
	for i = 1, #allParts do
		local part = allParts[i]
		local partIdx = part:GetAttribute("PartIndex")
		if typeOf(partIdx) == "number" then
			partDataMap[partIdx] = readPartData(part, mapFolder, partIdx)

			local isFalling = part:GetAttribute("IsFalling") == true
			part.Massless = false
			if isFalling then
				part.Anchored = false
				pcall(function()
					part:SetNetworkOwner(nil)
				end)
			else
				part.Anchored = true
			end
		end
		if i % yieldN == 0 then
			task.wait()
		end
	end

	NeighborTracker.BuildFromProximity(allParts, CFG.NEIGHBOR_SEARCH)

	local partMap: { [number]: BasePart } = {}
	for i = 1, #allParts do
		local part = allParts[i]
		local idx = part:GetAttribute("PartIndex")
		if typeOf(idx) == "number" then
			partMap[idx] = part
		end
	end

	local gapMax = CFG.AABB_GAP_MAX or 2.5
	for i = 1, #allParts do
		local partA = allParts[i]
		local idxA = partA:GetAttribute("PartIndex")
		if typeOf(idxA) == "number" then
			local neighbors = NeighborTracker.GetNeighbors(partA)
			if neighbors then
				local copy: { number } = {}
				for k = 1, #neighbors do
					copy[k] = neighbors[k]
				end
				for k = 1, #copy do
					local idxB = copy[k]
					local partB = partMap[idxB]
					if partB then
						if aabbGap(partA, partB) > gapMax then
							NeighborTracker.RemoveNeighbor(partA, idxB)
							NeighborTracker.RemoveNeighbor(partB, idxA)
						end
					end
				end
			end
		end
	end

	local weldsList: { any } = {}
	local weldCounter = 0

	for i = 1, #allParts do
		local partA = allParts[i]
		local idxA = partA:GetAttribute("PartIndex")
		if typeOf(idxA) == "number" then
			local fallingA = partA:GetAttribute("IsFalling") == true
			local neighbors = NeighborTracker.GetNeighbors(partA)
			if neighbors then
				for k = 1, #neighbors do
					local idxB = neighbors[k]
					if idxA < idxB then
						local partB = partMap[idxB]
						if partB then
							local fallingB = partB:GetAttribute("IsFalling") == true
							if fallingA == fallingB then
								local w = Instance.new("WeldConstraint")
								w.Part0 = partA
								w.Part1 = partB
								w.Parent = partA
								weldCounter = weldCounter + 1
								ins(weldsList, {
									WeldId = weldCounter,
									PartA = idxA,
									PartB = idxB,
									Constraint = w,
								})
							end
						end
					end
				end
			end
		end
		if i % yieldN == 0 then
			task.wait()
		end
	end

	return { Parts = partDataMap, Welds = weldsList }
end

function MapLoader.LoadMap(mapFolder: Instance): any
	return MapLoader.LoadMapAsChunks(mapFolder, math.huge)
end

return MapLoader
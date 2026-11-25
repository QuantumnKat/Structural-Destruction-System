--!strict
-- ReplicatedStorage.Shared.World.Spatial/GreedyMesh.luau

local GreedyMesher = {}

GreedyMesher.Config = {
	VoxelSize = 1,
	MaxChunkSize = 4,
	GroupByMaterial = false,
}

export type BoxData = {
	Pos: Vector3, CFrame: CFrame, Size: Vector3,
	PartIndex: number, MaterialId: number?,
}

local function getVoxelIndex(x: number, y: number, z: number, nx: number, ny: number): number
	return x + y * nx + z * nx * ny
end

local function maskOf(w: number): number
	return bit32.lshift(1, w) - 1
end

function GreedyMesher.Mesh(
	grid: { [number]: number },
	nx: number, ny: number, nz: number,
	originCFrame: CFrame,
	modelSize: Vector3,
	opts: any?
): { BoxData }
	opts = opts or {}
	local voxelSize  = opts.VoxelSize  or GreedyMesher.Config.VoxelSize
	local maxChunk = opts.MaxChunkSize or GreedyMesher.Config.MaxChunkSize
	if nx <= 30 then
		maxChunk = math.min(maxChunk, nx)
	end
	local groupByMat = opts.GroupByMaterial ~= nil and opts.GroupByMaterial or GreedyMesher.Config.GroupByMaterial
	local matOfPart  = opts.MaterialOfPart or {}
	local halfSize   = modelSize / 2
	local boxes      = {}

	local useBitmask = (nx <= 30)

	local keyOfPart: { [number]: number } = {}
	for i = 0, nx * ny * nz - 1 do
		local p = grid[i]
		if p and p > 0 and not keyOfPart[p] then
			keyOfPart[p] = groupByMat and (matOfPart[p] or p) or p
		end
	end

	local slices: { [number]: any } = {}
	for z = 0, nz - 1 do
		for y = 0, ny - 1 do
			local slice: any = { visitedMask = 0, visitedArr = {} }
			if useBitmask then
				slice.masks = {}
				for x = 0, nx - 1 do
					local p = grid[getVoxelIndex(x, y, z, nx, ny)]
					if p and p > 0 then
						local k = keyOfPart[p]
						slice.masks[k] = bit32.bor(slice.masks[k] or 0, bit32.lshift(1, x))
					end
				end
			else
				slice.keys = {}
				for x = 0, nx - 1 do
					local p = grid[getVoxelIndex(x, y, z, nx, ny)]
					if p and p > 0 then
						slice.keys[x] = keyOfPart[p]
					end
				end
			end
			slices[y * nz + z] = slice
		end
	end

	local function isVisited(slice, x: number): boolean
		if useBitmask then
			return bit32.band(slice.visitedMask, bit32.lshift(1, x)) ~= 0
		end
		return slice.visitedArr[x] == true
	end

	local function canRun(slice, k: number, x: number, w: number): boolean
		if x + w > nx then return false end
		if useBitmask then
			local expected = bit32.lshift(maskOf(w), x)
			local m = slice.masks[k] or 0
			if bit32.band(m, expected) ~= expected then return false end
			if bit32.band(slice.visitedMask, expected) ~= 0 then return false end
			return true
		else
			for i = x, x + w - 1 do
				if slice.keys[i] ~= k then return false end
				if slice.visitedArr[i] then return false end
			end
			return true
		end
	end

	local function mark(slice, x: number, w: number)
		if useBitmask then
			slice.visitedMask = bit32.bor(slice.visitedMask, bit32.lshift(maskOf(w), x))
		else
			for i = x, x + w - 1 do slice.visitedArr[i] = true end
		end
	end

	for z = 0, nz - 1 do
		for y = 0, ny - 1 do
			local slice = slices[y * nz + z]
			for x = 0, nx - 1 do
				local p = grid[getVoxelIndex(x, y, z, nx, ny)]
				if not p or p <= 0 then continue end
				if isVisited(slice, x) then continue end

				local k = keyOfPart[p]

				-- Expand X
				local w = 1
				while x + w < nx and w < maxChunk do
					if not canRun(slice, k, x, w + 1) then break end
					w += 1
				end

				-- Expand Z
				local d = 1
				while z + d < nz and d < maxChunk do
					local ok = true
					for ix = 0, w - 1 do
						local s2 = slices[y * nz + (z + d)]
						if not canRun(s2, k, x + ix, 1) then ok = false; break end
					end
					if not ok then break end
					d += 1
				end

				-- Expand Y
				local h = 1
				while y + h < ny and h < maxChunk do
					local ok = true
					for ix = 0, w - 1 do
						for iz = 0, d - 1 do
							local s2 = slices[(y + h) * nz + (z + iz)]
							if not canRun(s2, k, x + ix, 1) then ok = false; break end
						end
						if not ok then break end
					end
					if not ok then break end
					h += 1
				end

				-- Mark visited
				for iy = 0, h - 1 do
					for iz = 0, d - 1 do
						mark(slices[(y + iy) * nz + (z + iz)], x, w)
					end
				end

				local centerOffset = Vector3.new(
					(x + w / 2) * voxelSize - halfSize.X,
					(y + h / 2) * voxelSize - halfSize.Y,
					(z + d / 2) * voxelSize - halfSize.Z
				)
				local worldCF = originCFrame * CFrame.new(centerOffset)

				table.insert(boxes, {
					Pos = worldCF.Position, CFrame = worldCF,
					Size = Vector3.new(w * voxelSize, h * voxelSize, d * voxelSize),
					PartIndex = p,
					MaterialId = groupByMat and k or matOfPart[p],
				})
			end
		end
	end

	return boxes
end

function GreedyMesher.VoxelizePart(part: BasePart, opts: any?): { BoxData }
	opts = opts or {}
	local voxelSize = opts.VoxelSize or GreedyMesher.Config.VoxelSize
	local chunkSize = opts.MaxChunkSize or GreedyMesher.Config.MaxChunkSize
	local size      = part.Size
	local nx = math.max(1, math.ceil(size.X / voxelSize))
	local ny = math.max(1, math.ceil(size.Y / voxelSize))
	local nz = math.max(1, math.ceil(size.Z / voxelSize))
	local partIdx = part:GetAttribute("PartIndex") or 1
	local totalVox = nx * ny * nz

	local grid: { [number]: number } = {}
	for i = 0, totalVox - 1 do
		grid[i] = partIdx
	end

	return GreedyMesher.Mesh(grid, nx, ny, nz, part.CFrame, size, {
		VoxelSize = voxelSize, MaxChunkSize = chunkSize,
		GroupByMaterial = false,
		MaterialOfPart = { [partIdx] = part.Material.Value },
	})
end

function GreedyMesher.MarkAirInRadius(
	grid: { [number]: number },
	nx: number, ny: number, nz: number,
	originCFrame: CFrame, modelSize: Vector3,
	worldPos: Vector3, radius: number,
	voxelSize: number?
): { [number]: number }
	voxelSize = voxelSize or GreedyMesher.Config.VoxelSize
	local localPos = originCFrame:PointToObjectSpace(worldPos)
	local halfSize = modelSize / 2
	local r2 = radius * radius
	local removed: { [number]: number } = {}

	for z = 0, nz - 1 do
		for y = 0, ny - 1 do
			for x = 0, nx - 1 do
				local idx = getVoxelIndex(x, y, z, nx, ny)
				local p = grid[idx]
				if p and p > 0 then
					local cx = (x + 0.5) * voxelSize - halfSize.X
					local cy = (y + 0.5) * voxelSize - halfSize.Y
					local cz = (z + 0.5) * voxelSize - halfSize.Z
					local dx, dy, dz = cx - localPos.X, cy - localPos.Y, cz - localPos.Z
					if dx*dx + dy*dy + dz*dz <= r2 then
						removed[idx] = p
						grid[idx] = 0
					end
				end
			end
		end
	end
	return removed
end

function GreedyMesher.MarkAirPercent(
	grid: { [number]: number },
	nx: number, ny: number, nz: number,
	percent: number,
	rng: Random?
): { [number]: number }
	local r = rng or Random.new()
	local removed: { [number]: number } = {}
	for i = 0, nx * ny * nz - 1 do
		local p = grid[i]
		if p and p > 0 and r:NextNumber() < percent then
			removed[i] = p
			grid[i] = 0
		end
	end
	return removed
end

function GreedyMesher.RemovedVoxelsToBoxes(
	removed: { [number]: number },
	nx: number, ny: number, nz: number,
	originCFrame: CFrame, modelSize: Vector3,
	voxelSize: number?
): { BoxData }
	voxelSize = voxelSize or GreedyMesher.Config.VoxelSize
	local halfSize = modelSize / 2
	local boxes: { BoxData } = {}
	for idx, pIdx in pairs(removed) do
		local z = math.floor(idx / (nx * ny))
		local rem = idx - z * nx * ny
		local y = math.floor(rem / nx)
		local x = rem - y * nx
		local centerOffset = Vector3.new(
			(x + 0.5) * voxelSize - halfSize.X,
			(y + 0.5) * voxelSize - halfSize.Y,
			(z + 0.5) * voxelSize - halfSize.Z
		)
		local worldCF = originCFrame * CFrame.new(centerOffset)
		table.insert(boxes, {
			Pos = worldCF.Position, CFrame = worldCF,
			Size = Vector3.new(voxelSize, voxelSize, voxelSize),
			PartIndex = pIdx,
		})
	end
	return boxes
end

function GreedyMesher.VoxelizeModel(
	originCFrame: CFrame, modelSize: Vector3,
	parts: { BasePart }, partIndices: { [BasePart]: number }
): ({ [number]: number }, number, number, number)
	local voxelSize = GreedyMesher.Config.VoxelSize
	local nx = math.ceil(modelSize.X / voxelSize)
	local ny = math.ceil(modelSize.Y / voxelSize)
	local nz = math.ceil(modelSize.Z / voxelSize)
	local grid: { [number]: number } = {}
	local halfSize = modelSize / 2

	for z = 0, nz - 1 do
		for y = 0, ny - 1 do
			for x = 0, nx - 1 do
				local localCenter = Vector3.new(
					x * voxelSize + voxelSize / 2 - halfSize.X,
					y * voxelSize + voxelSize / 2 - halfSize.Y,
					z * voxelSize + voxelSize / 2 - halfSize.Z
				)
				local worldCenter = (originCFrame * CFrame.new(localCenter)).Position
				local currentPartIndex = 0
				for _, part in parts do
					local lp = part.CFrame:PointToObjectSpace(worldCenter)
					if math.abs(lp.X) <= part.Size.X / 2
						and math.abs(lp.Y) <= part.Size.Y / 2
						and math.abs(lp.Z) <= part.Size.Z / 2 then
						currentPartIndex = partIndices[part]
						break
					end
				end
				if currentPartIndex > 0 then
					grid[getVoxelIndex(x, y, z, nx, ny)] = currentPartIndex
				end
			end
		end
	end
	return grid, nx, ny, nz
end

return GreedyMesher

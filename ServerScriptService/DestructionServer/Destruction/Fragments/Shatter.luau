--!strict
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GreedyMesher      = require(ReplicatedStorage.Shared.World.Spatial.GreedyMesh)
local DebrisSpawner     = require(script.Parent.Parent.Fragments.DebrisSpawner)

local mathmax  = math.max
local mathceil = math.ceil
local mathrand = math.random

local MAX_VOXELS = 8192

local Shatter = {}

function Shatter.ShatterPart(
	part: BasePart,
	matRule: any,
	mode: string,
	impactCenter: Vector3,
	radius: number,
	camFolder: Instance,
	ActiveParts: { BasePart },
	debrisList: { any }
)
	if not part or not part.Parent then return end

	local size = part.Size
	local cframe = part.CFrame

	local voxelSize = GreedyMesher.Config and GreedyMesher.Config.VoxelSize
	if type(voxelSize) ~= "number" or voxelSize <= 0 then
		voxelSize = 2
	end
	local volume = size.X * size.Y * size.Z
	local minVoxel = (volume / MAX_VOXELS) ^ (1 / 3)
	if voxelSize < minVoxel then
		voxelSize = minVoxel
	end

	local chunkSize
	if mode == "Shatter" then
		chunkSize = (matRule and matRule.ShatterChunkSize)
			or (matRule and matRule.DebrisChunkSize)
			or 4
	else
		chunkSize = (matRule and matRule.DebrisChunkSize) or 4
	end

	local maxDebris = (matRule and matRule.MaxDebrisPerPart) or 64
	if maxDebris < 1 then maxDebris = 1 end

	local nx = mathmax(1, mathceil(size.X / voxelSize))
	local ny = mathmax(1, mathceil(size.Y / voxelSize))
	local nz = mathmax(1, mathceil(size.Z / voxelSize))
	local totalVox = nx * ny * nz
	local modelSize = Vector3.new(nx * voxelSize, ny * voxelSize, nz * voxelSize)

	local grid: { [number]: number } = {}
	for i = 0, totalVox - 1 do
		grid[i] = 1
	end

	local removed: { [number]: number }
	if mode == "Shatter" then
		local percent = (matRule and matRule.ShatterAirPercent) or 0.15
		removed = GreedyMesher.MarkAirPercent(grid, nx, ny, nz, percent)
	else
		removed = GreedyMesher.MarkAirInRadius(
			grid, nx, ny, nz, cframe, modelSize, impactCenter, radius, voxelSize
		)
	end

	local remainingBoxes = GreedyMesher.Mesh(grid, nx, ny, nz, cframe, modelSize, {
		VoxelSize = voxelSize,
		MaxChunkSize = chunkSize,
	})
	local removedBoxes = GreedyMesher.RemovedVoxelsToBoxes(
		removed, nx, ny, nz, cframe, modelSize, voxelSize
	)

	local allBoxes: { any } = {}
	for i = 1, #remainingBoxes do
		allBoxes[#allBoxes + 1] = remainingBoxes[i]
	end
	for i = 1, #removedBoxes do
		allBoxes[#allBoxes + 1] = removedBoxes[i]
	end

	for i = 1, #allBoxes do
		local b = allBoxes[i]
		if b then
			if not b.CFrame then
				if b.Pos then
					b.CFrame = CFrame.new(b.Pos)
				else
					b.Pos = cframe.Position
					b.CFrame = cframe
				end
			elseif not b.Pos then
				b.Pos = b.CFrame.Position
			end
		end
	end

	local total = #allBoxes
	if total > maxDebris then
		for i = total, 2, -1 do
			local j = mathrand(i)
			allBoxes[i], allBoxes[j] = allBoxes[j], allBoxes[i]
		end
		for i = total, maxDebris + 1, -1 do
			allBoxes[i] = nil
		end
	end

	if #allBoxes == 0 then return end

	if #allBoxes > 100 then
		task.wait()
	end

	DebrisSpawner.SpawnFromBoxes(
		allBoxes, part, matRule, impactCenter,
		camFolder, ActiveParts, debrisList
	)
end

return Shatter

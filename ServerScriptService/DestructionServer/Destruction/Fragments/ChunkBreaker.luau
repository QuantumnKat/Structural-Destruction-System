--!strict
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapSerializer     = require(ReplicatedStorage.Shared.Map.MapSerializer)
local NeighborTracker   = require(ReplicatedStorage.Shared.Destruction.NeighborTracker)
local ObjectConf        = require(script.Parent.Parent.Parent.Objects.ObjectConf)
local PhysicsHelpers    = require(script.Parent.Parent.Support.PhysicsHelpers)
local DebrisSpawner     = require(script.Parent.Parent.Fragments.DebrisSpawner)
local PartIds 			= require(script.Parent.Parent.Identity.PartIds)
local Constants         = require(script.Parent.Parent.Support.Constants)

local ins       = table.insert
local mathmax   = math.max
local mathmin   = math.min
local mathround = math.round
local mathfloor = math.floor
local mathabs   = math.abs
local mathexp   = math.exp

local BASE_VOXEL_SIZE = 2
local MAX_CHUNK_SIZE  = 8
local DEBRIS_CHUNK    = 4
local ATTACKER_WELD_LIFE = 0.25
local FIND_SUPPORT_MAX_DEPTH = 8

local ChunkBreaker = {}

local function getNextNodeIdx(graph: any): number
	if not graph._NextIdx then
		local m = 0
		for k in pairs(graph.Nodes) do
			if type(k) == "number" and k > m then m = k end
		end
		graph._NextIdx = m + 1
	end
	local n = graph._NextIdx
	graph._NextIdx = n + 1
	return n
end

local function getNextWeldId(graph: any): number
	if not graph._NextWeldId then
		graph._NextWeldId = 1_000_000
	end
	local n = graph._NextWeldId
	graph._NextWeldId = n + 1
	return n
end

local function findBestSupport(
	idx: number,
	graph: any,
	physicalPartMap: { [number]: BasePart },
	maxDepth: number
): BasePart?
	local queue: { { idx: number, depth: number } } = { { idx = idx, depth = 0 } }
	local visited: { [number]: boolean } = { [idx] = true }
	local head = 1

	while head <= #queue do
		local cur = queue[head]
		head = head + 1

		if cur.depth > 0 then
			local node = graph.Nodes[cur.idx]
			if node and node.IsActive and node.IsAnchor then
				local p = physicalPartMap[cur.idx]
				if p and p.Parent and p.Anchored and not p:GetAttribute("IsFalling") then
					return p
				end
			end
		end

		if cur.depth >= maxDepth then continue end

		local edges = graph.Edges[cur.idx]
		if edges then
			for i = 1, #edges do
				local e = edges[i]
				if graph.ActiveWelds[e.WeldId] ~= nil and not visited[e.Target] then
					visited[e.Target] = true
					ins(queue, { idx = e.Target, depth = cur.depth + 1 })
				end
			end
		end
	end

	return nil
end

local function classifyVoxels(
	oldCFrame: CFrame,
	oldSize: Vector3,
	nx: number, ny: number, nz: number,
	vx: number, vy: number, vz: number,
	carvePoint: Vector3,
	carveRadius: number,
	mode: string,
	supportPos: Vector3?,
	matRule: any,
	impactForce: number
): ({ [number]: number }, { [number]: number }, { [number]: number })
	local supported: { [number]: number } = {}
	local falling: { [number]: number } = {}
	local debris: { [number]: number } = {}

	local carveRadiusSq = carveRadius * carveRadius
	local lateralLimitSq = (carveRadius * 1.5) * (carveRadius * 1.5)
	local halfX, halfY, halfZ = oldSize.X * 0.5, oldSize.Y * 0.5, oldSize.Z * 0.5
	local strideZ = nx * ny

	local distToSupport: { [number]: number }? = nil
	if mode ~= "Carve" and supportPos then
		distToSupport = {}
		local searchRadius = mathmax(vx, mathmax(vy, vz)) * 1.5
		local queue: { number } = {}
		local visited: { [number]: boolean } = {}

		for z = 0, nz - 1 do
			for y = 0, ny - 1 do
				for x = 0, nx - 1 do
					local lp = Vector3.new(
						(x + 0.5) * vx - halfX,
						(y + 0.5) * vy - halfY,
						(z + 0.5) * vz - halfZ
					)
					local wp = oldCFrame * lp
					local d = (wp - supportPos).Magnitude
					if d <= searchRadius then
						local li = x + y * nx + z * strideZ
						distToSupport[li] = d
						visited[li] = true
						ins(queue, li)
					end
				end
			end
		end

		local head = 1
		local stepCost = mathmax(vx, mathmax(vy, vz))
		while head <= #queue do
			local cur = queue[head]
			head = head + 1
			local curDist = distToSupport[cur]
			local cx = cur % nx
			local cy = mathfloor(cur / nx) % ny
			local cz = mathfloor(cur / strideZ)

			if cx + 1 < nx then
				local nli = cur + 1
				if not visited[nli] then
					visited[nli] = true
					distToSupport[nli] = curDist + stepCost
					ins(queue, nli)
				end
			end
			if cx > 0 then
				local nli = cur - 1
				if not visited[nli] then
					visited[nli] = true
					distToSupport[nli] = curDist + stepCost
					ins(queue, nli)
				end
			end
			if cy + 1 < ny then
				local nli = cur + nx
				if not visited[nli] then
					visited[nli] = true
					distToSupport[nli] = curDist + stepCost
					ins(queue, nli)
				end
			end
			if cy > 0 then
				local nli = cur - nx
				if not visited[nli] then
					visited[nli] = true
					distToSupport[nli] = curDist + stepCost
					ins(queue, nli)
				end
			end
			if cz + 1 < nz then
				local nli = cur + strideZ
				if not visited[nli] then
					visited[nli] = true
					distToSupport[nli] = curDist + stepCost
					ins(queue, nli)
				end
			end
			if cz > 0 then
				local nli = cur - strideZ
				if not visited[nli] then
					visited[nli] = true
					distToSupport[nli] = curDist + stepCost
					ins(queue, nli)
				end
			end
		end
	end

	local baseBending = (matRule and matRule.BendingForce) or 300
	local baseTensile = (matRule and matRule.TensileStrength) or 150
	local impactDenom = carveRadius * 1.2
	if impactDenom < 0.001 then impactDenom = 0.001 end

	for z = 0, nz - 1 do
		for y = 0, ny - 1 do
			for x = 0, nx - 1 do
				local li = x + y * nx + z * strideZ
				local lp = Vector3.new(
					(x + 0.5) * vx - halfX,
					(y + 0.5) * vy - halfY,
					(z + 0.5) * vz - halfZ
				)
				local wp = oldCFrame * lp

				local dX = wp.X - carvePoint.X
				local dY = wp.Y - carvePoint.Y
				local dZ = wp.Z - carvePoint.Z
				local distToCarveSq = dX * dX + dY * dY + dZ * dZ
				local horizDistSq = dX * dX + dZ * dZ

				if mode == "Carve" then
					if distToCarveSq <= carveRadiusSq then
						debris[li] = 1
					elseif wp.Y <= carvePoint.Y + vy * 0.5 or horizDistSq > lateralLimitSq then
						supported[li] = 1
					else
						falling[li] = 1
					end
				else
					if not supportPos then
						falling[li] = 1
					elseif distToCarveSq <= carveRadiusSq then
						debris[li] = 1
					else
						local dSup = distToSupport and distToSupport[li]
						if dSup == nil then
							falling[li] = 1
						else
							local distFromImpact = math.sqrt(distToCarveSq)
							local forceAtVoxel = impactForce * mathexp(-distFromImpact / impactDenom)
							local decay = mathexp(-dSup * 0.1)
							local bendingRes = baseBending * decay
							local tensileRes = baseTensile * decay

							if forceAtVoxel > bendingRes and forceAtVoxel > tensileRes then
								debris[li] = 1
							elseif forceAtVoxel > 0.6 * bendingRes and forceAtVoxel > 0.6 * tensileRes then
								falling[li] = 1
							else
								supported[li] = 1
							end
						end
					end
				end
			end
		end
		if mode == "Carve" and z % 4 == 0 and z > 0 then
			task.wait()
		end
	end

	return supported, falling, debris
end

local function localGreedyMesh(
	grid: { [number]: number },
	nx: number, ny: number, nz: number,
	vx: number, vy: number, vz: number,
	oldCFrame: CFrame,
	oldSize: Vector3,
	maxDim: number,
	oldColor: Color3,
	oldMaterialValue: number
): { any }
	local boxes: { any } = {}
	if not grid or next(grid) == nil then return boxes end

	local visited: { [number]: boolean } = {}
	local strideZ = nx * ny
	local halfX, halfY, halfZ = oldSize.X * 0.5, oldSize.Y * 0.5, oldSize.Z * 0.5

	for z = 0, nz - 1 do
		for y = 0, ny - 1 do
			for x = 0, nx - 1 do
				local li = x + y * nx + z * strideZ
				if grid[li] and not visited[li] then
					local wx = 1
					while x + wx < nx and wx < maxDim do
						local nli = (x + wx) + y * nx + z * strideZ
						if grid[nli] and not visited[nli] then
							wx = wx + 1
						else
							break
						end
					end

					local hy = 1
					while y + hy < ny and hy < maxDim do
						local ok = true
						for dx = 0, wx - 1 do
							local nli = (x + dx) + (y + hy) * nx + z * strideZ
							if not grid[nli] or visited[nli] then
								ok = false
								break
							end
						end
						if ok then hy = hy + 1 else break end
					end

					local dz = 1
					while z + dz < nz and dz < maxDim do
						local ok = true
						for dy = 0, hy - 1 do
							for dx = 0, wx - 1 do
								local nli = (x + dx) + (y + dy) * nx + (z + dz) * strideZ
								if not grid[nli] or visited[nli] then
									ok = false
									break
								end
							end
							if not ok then break end
						end
						if ok then dz = dz + 1 else break end
					end

					for ddz = 0, dz - 1 do
						for ddy = 0, hy - 1 do
							for ddx = 0, wx - 1 do
								local nli = (x + ddx) + (y + ddy) * nx + (z + ddz) * strideZ
								visited[nli] = true
							end
						end
					end

					local size = Vector3.new(wx * vx, hy * vy, dz * vz)
					local centerLocal = Vector3.new(
						(x + wx * 0.5) * vx - halfX,
						(y + hy * 0.5) * vy - halfY,
						(z + dz * 0.5) * vz - halfZ
					)

					local cf = oldCFrame * CFrame.new(centerLocal)
					local finalPos = cf.Position

					ins(boxes, {
						Size = size,
						CFrame = cf,
						Position = finalPos,
						Pos = finalPos,
						Color = oldColor,
						Material = oldMaterialValue,
					})
				end
			end
		end
	end

	return boxes
end

function ChunkBreaker.BreakChunk(
	part: BasePart,
	idx: number,
	carvePoint: Vector3,
	carveRadius: number,
	impactCenter: Vector3,
	impactForce: number,
	graph: any,
	physicalPartMap: { [number]: BasePart },
	camFolder: Instance,
	ActiveParts: { BasePart },
	debrisList: { any },
	replicationEvent: RemoteEvent?,
	mode: string?,
	supportPos: Vector3?,
	forceFall: boolean?,
	attackerPart: BasePart?
): (boolean, { BasePart }?, { BasePart }?)
	if not part or not part.Parent then return false, nil, nil end
	if not graph.Nodes[idx] or not graph.Nodes[idx].IsActive then return false, nil, nil end

	mode = mode or "Carve"
	local matRule: any = ObjectConf.GetMaterialRule(part.Material)
	if matRule.Destroyable == false then return false, nil, nil end

	local oldCFrame = part.CFrame
	local oldSize = part.Size
	local oldColor = part.Color
	local oldName = part.Name
	local oldHP = part:GetAttribute("HP") or 100
	local oldMaterial = part.Material
	local oldMaterialValue = oldMaterial.Value

	local oldAttrs: { [string]: any } = {}
	for aName, aVal in pairs(part:GetAttributes()) do
		if aName ~= "PartIndex" and aName ~= "HP" and aName ~= "IsFalling" and aName ~= "ObjectId" then
			oldAttrs[aName] = aVal
		end
	end

	local nx = mathmax(1, mathround(oldSize.X / BASE_VOXEL_SIZE))
	local ny = mathmax(1, mathround(oldSize.Y / BASE_VOXEL_SIZE))
	local nz = mathmax(1, mathround(oldSize.Z / BASE_VOXEL_SIZE))
	local vx = oldSize.X / nx
	local vy = oldSize.Y / ny
	local vz = oldSize.Z / nz

	local supportPart: BasePart? = nil
	if not forceFall then
		supportPart = findBestSupport(idx, graph, physicalPartMap, FIND_SUPPORT_MAX_DEPTH)
		if not supportPart then
			local neighbors = NeighborTracker.GetNeighbors(part)
			if neighbors then
				for i = 1, #neighbors do
					local nid = neighbors[i]
					local np = physicalPartMap[nid]
					if np and np.Parent and np.Anchored and not np:GetAttribute("IsFalling") then
						supportPart = np
						break
					end
				end
			end
		end
	end

	local actualSupportPos = supportPos
	if not actualSupportPos and supportPart then
		actualSupportPos = supportPart.Position
	end

	local supportedGrid, fallingGrid, debrisGrid = classifyVoxels(
		oldCFrame, oldSize, nx, ny, nz, vx, vy, vz,
		carvePoint, carveRadius, mode, actualSupportPos, matRule, impactForce
	)

	if forceFall or not supportPart then
		for li, _ in pairs(supportedGrid) do
			fallingGrid[li] = 1
		end
		supportedGrid = {}
	end

	local mapFolder = camFolder:FindFirstChild("Map") or camFolder
	local cfg = graph.Config

	local function newVoxelPart(box, anchored, isFalling)
		local p = Instance.new("Part")
		p.Name = oldName
		p.Size = box.Size
		p.CFrame = box.CFrame
		p.Color = box.Color or oldColor
		p.Material = oldMaterial
		p.Anchored = anchored
		p.CanCollide = true
		p.CanQuery = true
		p.CanTouch = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth

		for aName, aVal in pairs(oldAttrs) do
			p:SetAttribute(aName, aVal)
		end
		p:SetAttribute("HP", oldHP)
		p:SetAttribute("IsFalling", isFalling)

		local newIdx = getNextNodeIdx(graph)
		p:SetAttribute("PartIndex", newIdx)
		p.Parent = mapFolder
		physicalPartMap[newIdx] = p

		local mass = p.Mass
		if not mass or mass <= 0 then
			mass = box.Size.X * box.Size.Y * box.Size.Z
			if mass <= 0 then mass = 1 end
		end

		graph.Nodes[newIdx] = {
			Index = newIdx,
			Name = p.Name,
			Position = p.Position,
			Size = p.Size,
			Mass = mass,
			HP = oldHP,
			TensileStrength = matRule.TensileStrength or cfg.DEFAULT_TENSILE,
			BendingForce = matRule.BendingForce or cfg.DEFAULT_BENDING,
			CompressionStrength = matRule.CompressionStrength or cfg.DEFAULT_COMPRESSION,
			ForceTransmission = matRule.ForceTransmission or 1,
			UnweldPercentage = nil,
			IsAnchor = false,
			IsActive = true,
			DeactivatedBy = nil,
			IslandId = nil,
			YFixed = mathfloor(p.Position.Y * cfg.FP_SCALE + 0.5),
		}
		graph.Edges[newIdx] = {}
		if graph._MarkDirty then
			graph:_MarkDirty(newIdx)
		end

		if isFalling then
			pcall(function()
				p:SetNetworkOwner(nil)
			end)
		end

		return p, newIdx
	end

	local supportedData: { any } = {}
	local supportedBoxes = localGreedyMesh(
		supportedGrid, nx, ny, nz, vx, vy, vz, oldCFrame, oldSize,
		MAX_CHUNK_SIZE, oldColor, oldMaterialValue
	)

	local supportIdxNum: number? = nil
	if supportPart and supportPart.Parent then
		local sidx = supportPart:GetAttribute("PartIndex")
		if type(sidx) == "number" and graph.Nodes[sidx] then
			supportIdxNum = sidx
		end
	end

	for i = 1, #supportedBoxes do
		local box = supportedBoxes[i]
		local p, newIdx = newVoxelPart(box, true, false)

		if supportIdxNum and supportPart and supportPart.Parent then
			local w = Instance.new("WeldConstraint")
			w.Part0 = p
			w.Part1 = supportPart
			w.Parent = p
			graph:AddWeld(getNextWeldId(graph), newIdx, supportIdxNum, w)
			NeighborTracker.AddNeighbor(p, supportIdxNum)
			NeighborTracker.AddNeighbor(supportPart, newIdx)
		end

		ins(supportedData, {
			Id = newIdx,
			Size = box.Size,
			CFrame = box.CFrame,
			Color = box.Color,
			Material = box.Material,
		})
	end

	local debrisBoxes = localGreedyMesh(
		debrisGrid, nx, ny, nz, vx, vy, vz, oldCFrame, oldSize,
		DEBRIS_CHUNK, oldColor, oldMaterialValue
	)

	local validDebrisBoxes: { any } = {}
	for i = 1, #debrisBoxes do
		local box = debrisBoxes[i]
		if box and box.Size and box.CFrame and (box.Position or box.Pos) then
			ins(validDebrisBoxes, box)
		end
	end

	local debrisParts: { BasePart } = {}
	if #validDebrisBoxes > 0 then
		debrisParts = DebrisSpawner.SpawnFromBoxes(
			validDebrisBoxes, part, matRule, impactCenter,
			camFolder, ActiveParts, debrisList
		) or {}
	end
	
	local srcUid = part:GetAttribute("AttackerUserId")
	if type(srcUid) == "number" then
		local srcDmg = part:GetAttribute("AttributionDamage")
		local srcExp = part:GetAttribute("AttributionExpire")
		for i = 1, #debrisParts do
			local dp = debrisParts[i]
			dp:SetAttribute("AttackerUserId", srcUid)
			dp:SetAttribute("AttributionDamage", srcDmg)
			dp:SetAttribute("AttributionExpire", srcExp)
		end
	end

	local fallingBoxes = localGreedyMesh(
		fallingGrid, nx, ny, nz, vx, vy, vz, oldCFrame, oldSize,
		MAX_CHUNK_SIZE, oldColor, oldMaterialValue
	)

	local fallParts: { BasePart } = {}
	local fallNewIdxs: { number } = {}

	for i = 1, #fallingBoxes do
		local box = fallingBoxes[i]
		local p, newIdx = newVoxelPart(box, false, true)
		ins(fallParts, p)
		ins(fallNewIdxs, newIdx)
		ins(debrisList, {
			Id = newIdx + Constants.FALLING_ID_OFFSET,
			CFrame = box.CFrame,
			Size = box.Size,
			Color = box.Color,
			Material = box.Material,
		})
	end

	if #fallParts > 0 then
		local root = fallParts[1]
		local rootIdx = fallNewIdxs[1]
		for i = 1, #fallParts do
			local fid = Constants.FALLING_ID_OFFSET + fallNewIdxs[i]
			fallParts[i]:SetAttribute("ObjectId", fid)
			PartIds.Register(fallParts[i], fid)
			ins(ActiveParts, fallParts[i])
		end

		for i = 2, #fallParts do
			local p = fallParts[i]
			local pIdx = fallNewIdxs[i]
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = root
			graph:AddWeld(getNextWeldId(graph), rootIdx, pIdx, w)
			NeighborTracker.AddNeighbor(root, pIdx)
			NeighborTracker.AddNeighbor(p, rootIdx)
		end

		if attackerPart and attackerPart.Parent then
			local attackerIdx = attackerPart:GetAttribute("PartIndex")
			if type(attackerIdx) == "number" and graph.Nodes[attackerIdx] then
				local aw = Instance.new("WeldConstraint")
				aw.Part0 = root
				aw.Part1 = attackerPart
				aw.Parent = root
				graph:AddWeld(getNextWeldId(graph), rootIdx, attackerIdx, aw)
				task.delay(ATTACKER_WELD_LIFE, function()
					if aw and aw.Parent then aw:Destroy() end
				end)
			end
		end

		for i = 1, #fallParts do
			local p = fallParts[i]
			PhysicsHelpers.ApplyFallingPhysics(p, matRule)
			p:SetAttribute("IsFalling", true)
			p:SetAttribute("_SpawnTime", os.clock())
		end
	end

	local oldNeighbors = NeighborTracker.GetNeighbors(part)
	if oldNeighbors then
		local copy: { number } = {}
		for i = 1, #oldNeighbors do
			copy[i] = oldNeighbors[i]
		end
		for i = 1, #copy do
			local nid = copy[i]
			local np = physicalPartMap[nid]
			if np then
				NeighborTracker.RemoveNeighbor(np, idx)
			end
			NeighborTracker.RemoveNeighbor(part, nid)
		end
	end

	local oldEdges = graph.Edges[idx]
	if oldEdges then
		local wids: { number } = {}
		for i = 1, #oldEdges do
			ins(wids, oldEdges[i].WeldId)
		end
		for i = 1, #wids do
			graph:RemoveWeld(wids[i])
		end
	end

	local children = part:GetChildren()
	for i = 1, #children do
		local c = children[i]
		if c:IsA("WeldConstraint") or c:IsA("Weld") then
			c:Destroy()
		end
	end

	part:Destroy()
	physicalPartMap[idx] = nil
	graph:DeactivateNode(idx, "Chunk")

	if replicationEvent and #supportedData > 0 then
		local serialized
		if MapSerializer.SerializeDebris then
			serialized = MapSerializer.SerializeDebris(supportedData)
		elseif MapSerializer.Serialize then
			serialized = MapSerializer.Serialize(supportedData)
		end
		if serialized then
			replicationEvent:FireAllClients("CREATE_STATIC_PARTS", serialized)
		end
	end
	
	if _attributionTransfer then
		local newIds: { number } = {}
		for i = 1, #fallParts do
			local oid = fallParts[i]:GetAttribute("ObjectId")
			if type(oid) == "number" then newIds[#newIds + 1] = oid end
		end
		for i = 1, #debrisParts do
			local oid = debrisParts[i]:GetAttribute("ObjectId")
			if type(oid) == "number" then newIds[#newIds + 1] = oid end
		end
		if #newIds > 0 then _attributionTransfer(idx, newIds) end
	end

	return true, fallParts, debrisParts
end

return ChunkBreaker

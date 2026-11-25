--!strict
--!native

local StructureGraph = {}
StructureGraph.__index = StructureGraph

export type Config = {
	BASE_VOXEL_SIZE: number,
	COLUMN_CELL_SIZE: number,
	DAMAGE_K: number,
	DAMAGE_RECOVERY: number,
	DAMAGE_EPS: number,
	DEFAULT_SIGMA_ALLOW: number,
	DEFAULT_TAU_ALLOW: number,
	DEFAULT_BENDING: number,
	DEFAULT_TENSILE: number,
	DEFAULT_COMPRESSION: number,
	DEFAULT_DT: number,
	FRAME_BUDGET_NODES: number,
	MAX_STABILITY_PASSES: number,
	TOPO_EPS: number,
	FP_SCALE: number,
	ANCHOR_BFS_MAX_NODES: number,
}

export type Node = {
	Index: number,
	Name: string,
	Position: Vector3,
	Size: Vector3,
	Mass: number,
	HP: number,
	TensileStrength: number,
	BendingForce: number,
	CompressionStrength: number,
	ForceTransmission: number,
	UnweldPercentage: number?,
	IsAnchor: boolean,
	IsActive: boolean,
	DeactivatedBy: string?,
	IslandId: number?,
	YFixed: number,
}

export type Edge = {
	Target: number,
	WeldId: number,
	Constraint: WeldConstraint?,
	damage_contact: number,
	A_contact: number,
	sigma_allow: number,
	tau_allow: number,
	I_contact: number,
	last_sigma: number,
	last_tau: number,
}

export type FractureRequest = {
	idx: number,
	pos: Vector3,
	supportPos: Vector3,
	severity: number,
}

export type StructureGraphT = {
	Config: Config,
	Nodes: { [number]: Node },
	Edges: { [number]: { Edge } },
	ActiveWelds: { [number]: boolean },
	[string]: any,
}

local DEFAULT_CONFIG: Config = {
	BASE_VOXEL_SIZE   = 2.0,
	COLUMN_CELL_SIZE  = 2.0,
	DAMAGE_K = 0.15,
	DAMAGE_RECOVERY   = 0.02,
	DAMAGE_EPS        = 0.001,
	DEFAULT_SIGMA_ALLOW = 800,
	DEFAULT_TAU_ALLOW   = 300,
	DEFAULT_BENDING     = 300,
	DEFAULT_TENSILE     = 150,
	DEFAULT_COMPRESSION = 800,
	DEFAULT_DT          = 1 / 60,
	FRAME_BUDGET_NODES  = 200,
	MAX_STABILITY_PASSES = 8,
	TOPO_EPS            = 0.01,
	FP_SCALE            = 65536,
	ANCHOR_BFS_MAX_NODES = 5000,
}

local GRAVITY = 196.2

local VALID_REASONS: { [string]: boolean } = {
	Hit = true,
	Collapse = true,
	Shatter = true,
	Impact = true,
	Chunk = true,
	StressBreak = true,
	SupportBreak = true,
}

function StructureGraph.new(payload: any, config: Config?)
	local self = setmetatable({}, StructureGraph) :: any

	self.Config = {}
	for k, v in pairs(DEFAULT_CONFIG) do
		self.Config[k] = v
	end
	if config then
		for k, v in pairs(config) do
			self.Config[k] = v
		end
	end

	self.Nodes = {}
	self.Edges = {}
	self.ActiveWelds = {}
	self.WeldConstraints = {}
	self.WeldEnds = {}
	self._DirtyNodes = {}
	self._DirtyEdges = {}
	self._PendingBreaks = {}
	self._Damaged = {}
	self._MassColumn = {}
	self._ColumnValid = {}
	self._AxialLoadCache = {}
	self._GroundedCache = nil
	self._GroundedValid = false
	self._NextIslandId = 1
	self._LastTickTime = 0
	self._LastBrokenCount = 0
	self._StressedEdges = {}

	local fp = self.Config.FP_SCALE

	for i, p in pairs(payload.Parts) do
		local size = p.Size
		local pos = (p.CFrame and p.CFrame.Position) or p.Position
		local mass = p.Mass or 0
		if mass <= 0 then
			mass = size.X * size.Y * size.Z
			if mass <= 0 then mass = 1 end
		end
		self.Nodes[i] = {
			Index = i,
			Name = p.Name or ("Part" .. i),
			Position = pos,
			Size = size,
			Mass = mass,
			HP = p.HP or 100,
			TensileStrength = p.TensileStrength or self.Config.DEFAULT_TENSILE,
			BendingForce = p.BendingForce or self.Config.DEFAULT_BENDING,
			CompressionStrength = p.CompressionStrength or self.Config.DEFAULT_COMPRESSION,
			ForceTransmission = p.ForceTransmission or 1,
			UnweldPercentage = p.UnweldPercentage,
			IsAnchor = (p.Category == 3),
			IsActive = true,
			DeactivatedBy = nil,
			IslandId = nil,
			YFixed = math.floor(pos.Y * fp + 0.5),
		}
		self.Edges[i] = {}
		self._DirtyNodes[i] = true
	end

	if payload.Welds then
		for k, w in pairs(payload.Welds) do
			local wid = w.WeldId or k
			self:AddWeld(wid, w.PartA, w.PartB, w.Constraint)
		end
	end

	return self
end

function StructureGraph:AddWeld(weldId: number, partA: number, partB: number, constraint: WeldConstraint?)
	local nodeA = self.Nodes[partA]
	local nodeB = self.Nodes[partB]
	if not nodeA or not nodeB or partA == partB then return end
	if self.ActiveWelds[weldId] then return end

	local ovX = math.min(nodeA.Position.X + nodeA.Size.X * 0.5, nodeB.Position.X + nodeB.Size.X * 0.5)
	- math.max(nodeA.Position.X - nodeA.Size.X * 0.5, nodeB.Position.X - nodeB.Size.X * 0.5)
	local ovZ = math.min(nodeA.Position.Z + nodeA.Size.Z * 0.5, nodeB.Position.Z + nodeB.Size.Z * 0.5)
	- math.max(nodeA.Position.Z - nodeA.Size.Z * 0.5, nodeB.Position.Z - nodeB.Size.Z * 0.5)
	if ovX <= 0 or ovZ <= 0 then
		ovX = math.min(nodeA.Size.X, nodeB.Size.X)
		ovZ = math.min(nodeA.Size.Z, nodeB.Size.Z)
	end
	local A_contact = math.max(ovX * ovZ, 0.25)
	local I_contact = (A_contact * A_contact) / 12

	local sigma_allow = math.min(nodeA.CompressionStrength, nodeB.CompressionStrength)
	local tau_allow = math.min(nodeA.TensileStrength * 0.5, nodeB.TensileStrength * 0.5)

	local edgeAB: Edge = {
		Target = partB, WeldId = weldId, Constraint = constraint,
		damage_contact = 0, A_contact = A_contact, I_contact = I_contact,
		sigma_allow = sigma_allow, tau_allow = tau_allow,
		last_sigma = 0, last_tau = 0,
	}
	local edgeBA: Edge = {
		Target = partA, WeldId = weldId, Constraint = constraint,
		damage_contact = 0, A_contact = A_contact, I_contact = I_contact,
		sigma_allow = sigma_allow, tau_allow = tau_allow,
		last_sigma = 0, last_tau = 0,
	}
	table.insert(self.Edges[partA], edgeAB)
	table.insert(self.Edges[partB], edgeBA)
	self.ActiveWelds[weldId] = true
	self.WeldConstraints[weldId] = constraint
	self.WeldEnds[weldId] = { partA, partB }
end

function StructureGraph:_FindEdge(weldId: number): Edge?
	local ends = self.WeldEnds[weldId]
	if not ends then return nil end
	local list = self.Edges[ends[1]]
	if not list then return nil end
	for _, e in ipairs(list) do
		if e.WeldId == weldId then
			return e
		end
	end
	return nil
end

function StructureGraph:_Mirror(edge: Edge): Edge?
	local list = self.Edges[edge.Target]
	if not list then return nil end
	for _, m in ipairs(list) do
		if m.WeldId == edge.WeldId and m ~= edge then
			return m
		end
	end
	return nil
end

function StructureGraph:RemoveWeld(weldId: number)
	if self.ActiveWelds[weldId] == nil then return end
	local c = self.WeldConstraints[weldId]
	if c and c.Parent then
		c:Destroy()
	end
	self.ActiveWelds[weldId] = nil
	self.WeldConstraints[weldId] = nil
	self._Damaged[weldId] = nil
	self._PendingBreaks[weldId] = nil
	local ends = self.WeldEnds[weldId]
	if ends then
		self._DirtyNodes[ends[1]] = true
		self._DirtyNodes[ends[2]] = true
	end
	self:_MarkDirtyEdge(weldId)
end

function StructureGraph:DeactivateNode(partIndex: number, reason: string?): boolean
	local node = self.Nodes[partIndex]
	if not node or not node.IsActive or node.IsAnchor then
		return false
	end
	if reason and not VALID_REASONS[reason] then
		reason = "Unknown"
	end
	node.IsActive = false
	node.DeactivatedBy = reason or "Unknown"

	local edges = self.Edges[partIndex]
	if edges then
		local wids = {}
		for _, e in ipairs(edges) do
			table.insert(wids, e.WeldId)
		end
		for _, wid in ipairs(wids) do
			self:RemoveWeld(wid)
		end
	end

	self:_MarkDirty(partIndex)
	self:_InvalidateColumnForNode(node)
	self._GroundedValid = false
	return true
end

function StructureGraph:_InvalidateColumnForNode(node: Node)
	local cellSize = self.Config.COLUMN_CELL_SIZE
	local cx = math.floor(node.Position.X / cellSize)
	local cz = math.floor(node.Position.Z / cellSize)
	local key = cx .. "," .. cz
	self._ColumnValid[key] = nil
end

function StructureGraph:GetGroundedNodes(): { [number]: boolean }
	if self._GroundedValid and self._GroundedCache then
		return self._GroundedCache
	end

	local grounded: { [number]: boolean } = {}
	local queue: { number } = {}
	local head = 1

	for idx, node in pairs(self.Nodes) do
		if node.IsActive and node.IsAnchor then
			grounded[idx] = true
			table.insert(queue, idx)
		end
	end

	while head <= #queue do
		local cur = queue[head]
		head = head + 1
		local edges = self.Edges[cur]
		if edges then
			for _, e in ipairs(edges) do
				if self.ActiveWelds[e.WeldId] ~= nil and not grounded[e.Target] then
					local tgt = self.Nodes[e.Target]
					if tgt and tgt.IsActive then
						grounded[e.Target] = true
						table.insert(queue, e.Target)
					end
				end
			end
		end
	end

	self._GroundedCache = grounded
	self._GroundedValid = true
	return grounded
end

function StructureGraph:GetEdgeBetween(a: number, b: number): Edge?
	local edges = self.Edges[a]
	if not edges then return nil end
	for _, e in ipairs(edges) do
		if e.Target == b and self.ActiveWelds[e.WeldId] ~= nil then
			return e
		end
	end
	return nil
end

function StructureGraph:_MarkDirty(idx: number)
	self._DirtyNodes[idx] = true
end

function StructureGraph:_MarkDirtyEdge(weldId: number)
	self._DirtyEdges[weldId] = true
	self._GroundedValid = false
end

function StructureGraph:RebuildDirtyIslands()
	local visited: { [number]: boolean } = {}

	for idx, _ in pairs(self._DirtyNodes) do
		local node = self.Nodes[idx]
		if not node or not node.IsActive then
			if node then node.IslandId = nil end
			visited[idx] = true
		end
	end

	for idx, _ in pairs(self._DirtyNodes) do
		if visited[idx] then continue end
		local node = self.Nodes[idx]
		if not node or not node.IsActive then continue end

		visited[idx] = true
		local islandId = self._NextIslandId
		self._NextIslandId = self._NextIslandId + 1
		node.IslandId = islandId

		local queue: { number } = { idx }
		local head = 1
		while head <= #queue do
			local cur = queue[head]
			head = head + 1
			local edges = self.Edges[cur]
			if edges then
				for _, e in ipairs(edges) do
					if self.ActiveWelds[e.WeldId] ~= nil and not visited[e.Target] then
						local tgt = self.Nodes[e.Target]
						if tgt and tgt.IsActive then
							visited[e.Target] = true
							tgt.IslandId = islandId
							table.insert(queue, e.Target)
						end
					end
				end
			end
		end
	end

	self._DirtyNodes = {}
	self._DirtyEdges = {}
end

function StructureGraph:ComputeAxialLoad()
	local cellSize = self.Config.COLUMN_CELL_SIZE
	local columns: { [string]: { number } } = {}

	for idx, node in pairs(self.Nodes) do
		if node.IsActive then
			local cx = math.floor(node.Position.X / cellSize)
			local cz = math.floor(node.Position.Z / cellSize)
			local key = cx .. "," .. cz
			local list = columns[key]
			if not list then
				list = {}
				columns[key] = list
			end
			table.insert(list, idx)
		end
	end

	for key, list in pairs(columns) do
		if not self._ColumnValid[key] then
			local old = self._MassColumn[key]
			if old then
				for _, oidx in ipairs(old) do
					self._AxialLoadCache[oidx] = nil
				end
			end

			table.sort(list, function(a, b)
				local na = self.Nodes[a]
				local nb = self.Nodes[b]
				if na.YFixed ~= nb.YFixed then
					return na.YFixed > nb.YFixed
				end
				return a < b
			end)

			local accum = 0
			for _, idx in ipairs(list) do
				accum = accum + self.Nodes[idx].Mass
				self._AxialLoadCache[idx] = accum
			end

			self._MassColumn[key] = list
			self._ColumnValid[key] = true
		end
	end

	for key, list in pairs(self._MassColumn) do
		if not columns[key] then
			for _, oidx in ipairs(list) do
				self._AxialLoadCache[oidx] = nil
			end
			self._MassColumn[key] = nil
			self._ColumnValid[key] = nil
		end
	end
end

function StructureGraph:PropagateLoadTopDown()
	local grounded = self:GetGroundedNodes()

	for _, list in pairs(self.Edges) do
		for _, e in ipairs(list) do
			e.last_sigma = 0
			e.last_tau = 0
		end
	end

	local sorted: { number } = {}
	for idx, node in pairs(self.Nodes) do
		if node.IsActive and grounded[idx] then
			table.insert(sorted, idx)
		end
	end

	table.sort(sorted, function(a, b)
		local na = self.Nodes[a]
		local nb = self.Nodes[b]
		if na.YFixed ~= nb.YFixed then
			return na.YFixed > nb.YFixed
		end
		return a < b
	end)

	self._StressedEdges = {}
	local epsFixed = self.Config.TOPO_EPS * self.Config.FP_SCALE

	local loadM: { [number]: number } = {}
	local loadX: { [number]: number } = {}
	local loadZ: { [number]: number } = {}
	for _, idx in ipairs(sorted) do
		local n = self.Nodes[idx]
		loadM[idx] = n.Mass
		loadX[idx] = n.Mass * n.Position.X
		loadZ[idx] = n.Mass * n.Position.Z
	end

	for _, idx in ipairs(sorted) do
		local node = self.Nodes[idx]
		local edges = self.Edges[idx]
		if not edges then continue end

		local lower: { Edge } = {}
		local cxs: { number } = {}
		local czs: { number } = {}
		local totalArea = 0
		local sumX = 0
		local sumZ = 0

		for _, e in ipairs(edges) do
			if self.ActiveWelds[e.WeldId] ~= nil then
				local tgt = self.Nodes[e.Target]
				if tgt and tgt.IsActive and grounded[e.Target] and tgt.YFixed < node.YFixed - epsFixed then
					local minX = math.max(node.Position.X - node.Size.X * 0.5, tgt.Position.X - tgt.Size.X * 0.5)
					local maxX = math.min(node.Position.X + node.Size.X * 0.5, tgt.Position.X + tgt.Size.X * 0.5)
					local minZ = math.max(node.Position.Z - node.Size.Z * 0.5, tgt.Position.Z - tgt.Size.Z * 0.5)
					local maxZ = math.min(node.Position.Z + node.Size.Z * 0.5, tgt.Position.Z + tgt.Size.Z * 0.5)
					local cx = if minX <= maxX then (minX + maxX) * 0.5 else tgt.Position.X
					local cz = if minZ <= maxZ then (minZ + maxZ) * 0.5 else tgt.Position.Z

					table.insert(lower, e)
					table.insert(cxs, cx)
					table.insert(czs, cz)
					totalArea = totalArea + e.A_contact
					sumX = sumX + e.A_contact * cx
					sumZ = sumZ + e.A_contact * cz
				end
			end
		end

		if #lower == 0 then continue end
		if totalArea < 1e-6 then totalArea = 1e-6 end

		local M = loadM[idx]
		local comX = loadX[idx] / M
		local comZ = loadZ[idx] / M
		local ex = comX - sumX / totalArea
		local ez = comZ - sumZ / totalArea
		local ecc = math.sqrt(ex * ex + ez * ez)

		for i, e in ipairs(lower) do
			local share = e.A_contact / totalArea
			local W_AB = M * GRAVITY * share

			local sigma_comp = W_AB / e.A_contact
			local c = math.sqrt(e.A_contact) * 0.5
			local sigma_bend = (ecc * W_AB * c) / e.I_contact
			local sigma_total = sigma_comp + sigma_bend

			e.last_sigma = sigma_total
			e.last_tau = 0

			local other = self:_Mirror(e)
			if other then
				other.last_sigma = math.max(other.last_sigma, sigma_total)
			end

			table.insert(self._StressedEdges, e)

			local tid = e.Target
			if loadM[tid] then
				local m = M * share
				loadM[tid] = loadM[tid] + m
				loadX[tid] = loadX[tid] + m * cxs[i]
				loadZ[tid] = loadZ[tid] + m * czs[i]
			end
		end
	end
end

function StructureGraph:ApplySingleStress(
	edge: Edge, sigma: number, tau: number, dt: number
): boolean
	local cfg = self.Config

	local sigmaAllow = edge.sigma_allow
	local tauAllow = edge.tau_allow

	local excessSig = 0
	if sigmaAllow > 0 and sigma > sigmaAllow then
		excessSig = (sigma - sigmaAllow) / sigmaAllow
	end
	local excessTau = 0
	if tauAllow > 0 and tau > tauAllow then
		excessTau = (tau - tauAllow) / tauAllow
	end
	local excess = math.max(excessSig, excessTau)

	local dmg = edge.damage_contact
	if excess > 0 then
		dmg = dmg + cfg.DAMAGE_K * excess * dt
	else
		dmg = dmg - cfg.DAMAGE_RECOVERY * dt
	end
	dmg = math.clamp(dmg, 0, 1)

	edge.damage_contact = dmg
	edge.last_sigma = sigma
	edge.last_tau = tau

	local mirror = self:_Mirror(edge)
	if mirror then
		mirror.damage_contact = dmg
		if sigma > mirror.last_sigma then mirror.last_sigma = sigma end
		if tau > mirror.last_tau then mirror.last_tau = tau end
	end

	if dmg > 0 then
		self._Damaged[edge.WeldId] = true
	else
		self._Damaged[edge.WeldId] = nil
	end

	return dmg >= 1 - cfg.DAMAGE_EPS
end

function StructureGraph:ApplyContactStress(dt: number)
	local processed: { [number]: boolean } = {}

	for _, e in ipairs(self._StressedEdges) do
		local wid = e.WeldId
		if not processed[wid] and self.ActiveWelds[wid] ~= nil then
			processed[wid] = true
			if self:ApplySingleStress(e, e.last_sigma, e.last_tau, dt) then
				self._PendingBreaks[wid] = true
			end
		end
	end

	for wid, _ in pairs(self._Damaged) do
		if not processed[wid] then
			local e = self:_FindEdge(wid)
			if e and self.ActiveWelds[wid] ~= nil then
				self:ApplySingleStress(e, 0, 0, dt)
			else
				self._Damaged[wid] = nil
			end
		end
	end
end

function StructureGraph:BreakDamagedEdges(): { number }
	local out: { number } = {}
	for weldId, _ in pairs(self._PendingBreaks) do
		if self.ActiveWelds[weldId] ~= nil then
			self:RemoveWeld(weldId)
			table.insert(out, weldId)
		end
	end
	self._PendingBreaks = {}
	return out
end

function StructureGraph:CollectNodesToDetach(): { number }
	local grounded = self:GetGroundedNodes()
	local out: { number } = {}
	for idx, node in pairs(self.Nodes) do
		if node.IsActive and not node.IsAnchor and not grounded[idx] then
			table.insert(out, idx)
		end
	end
	return out
end

function StructureGraph:CollectNodesToFracture(): { FractureRequest }
	local grounded = self:GetGroundedNodes()
	local out: { FractureRequest } = {}
	local epsFixed = self.Config.TOPO_EPS * self.Config.FP_SCALE

	for idx, node in pairs(self.Nodes) do
		if not node.IsActive or not grounded[idx] then continue end

		local edges = self.Edges[idx]
		if not edges then continue end

		local maxRatio = 0
		local supportPos = node.Position
		local foundSupport = false

		for _, e in ipairs(edges) do
			if self.ActiveWelds[e.WeldId] ~= nil then
				local rs = e.sigma_allow > 0 and (e.last_sigma / e.sigma_allow) or 0
				local rt = e.tau_allow > 0 and (e.last_tau / e.tau_allow) or 0
				local r = math.max(rs, rt)
				if r > maxRatio then maxRatio = r end

				local tgt = self.Nodes[e.Target]
				if tgt and tgt.IsActive and tgt.YFixed < node.YFixed - epsFixed and not foundSupport then
					supportPos = tgt.Position
					foundSupport = true
				end
			end
		end

		if maxRatio > 2.5 then
			local severity = math.max(0, maxRatio - 1)
			table.insert(out, {
				idx = idx,
				pos = node.Position,
				supportPos = supportPos,
				severity = severity,
			})
		end
	end

	return out
end

function StructureGraph:Tick(dt: number): ({ number }, { FractureRequest })
	self:RebuildDirtyIslands()
	self:PropagateLoadTopDown()
	self:ApplyContactStress(dt)
	local broken = self:BreakDamagedEdges()
	self._LastBrokenCount = #broken

	local detach = self:CollectNodesToDetach()
	local fracture = self:CollectNodesToFracture()

	self._LastTickTime = os.clock()
	return detach, fracture
end

function StructureGraph:CheckStability(): ({ FractureRequest }, { number })
	local dt = self.Config.DEFAULT_DT
	local allDetach: { number } = {}
	local allFracture: { FractureRequest } = {}
	local fracturedSet: { [number]: boolean } = {}

	for _ = 1, self.Config.MAX_STABILITY_PASSES do
		local detach, fracture = self:Tick(dt)

		local newFracture = 0
		for _, f in ipairs(fracture) do
			if not fracturedSet[f.idx] then
				fracturedSet[f.idx] = true
				table.insert(allFracture, f)
				newFracture = newFracture + 1
			end
		end

		if #detach == 0 and newFracture == 0 and self._LastBrokenCount == 0 then
			break
		end

		for _, d in ipairs(detach) do
			table.insert(allDetach, d)
			self:DeactivateNode(d, "StressBreak")
		end
	end

	return allFracture, allDetach
end

function StructureGraph:DumpState(): string
	local parts: { string } = {}
	for idx, n in pairs(self.Nodes) do
		table.insert(parts, string.format(
			"Node %d: %s pos=(%.2f,%.2f,%.2f) m=%.2f active=%s island=%s",
			idx, n.Name, n.Position.X, n.Position.Y, n.Position.Z,
			n.Mass, tostring(n.IsActive), tostring(n.IslandId)
			))
	end
	local edgeParts: { string } = {}
	for idx, edges in pairs(self.Edges) do
		for _, e in ipairs(edges) do
			if self.ActiveWelds[e.WeldId] ~= nil then
				table.insert(edgeParts, string.format(
					"Edge %d->%d wid=%d dmg=%.3f sig=%.1f tau=%.1f",
					idx, e.Target, e.WeldId, e.damage_contact, e.last_sigma, e.last_tau
					))
			end
		end
	end
	return table.concat(parts, "\n") .. "\n--\n" .. table.concat(edgeParts, "\n")
end

return StructureGraph

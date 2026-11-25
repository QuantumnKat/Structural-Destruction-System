--!strict
--!native

local StructureGraph = require(script.Parent.StructureGraph)

type Graph  = StructureGraph.StructureGraphT
type Edge   = StructureGraph.Edge
type Node   = StructureGraph.Node
type Config = StructureGraph.Config

export type ImpactInfo = {
	idx: number,
	force: number,
	dist: number,
}

export type PropagateResult = {
	brokenEdges: { [number]: boolean },
	impactsList: { ImpactInfo },
}

export type Seed = {
	idx: number,
	force: number,
	dir: Vector3?,
}

local DEFAULT_DECAY          = 0.75
local MIN_FORCE_EPS          = 5.0
local DEFAULT_DT             = 0.05
local PILLAR_BONUS_K         = 4.0
local PILLAR_BONUS_DECAY     = 0.15
local BROKEN_FORCE_KEEP      = 0.3
local MAX_BFS_ITER           = 20000
local DOWN                   = Vector3.new(0, -1, 0)

local ForcePropagator = {}

local function computeAnchorDistances(graph: Graph, maxRadius: number): { [number]: number }
	local nodes = graph.Nodes
	local edges = graph.Edges
	local active = graph.ActiveWelds

	local dist: { [number]: number } = {}
	local queue: { number } = {}
	local head = 1

	for idx, node in pairs(nodes) do
		if node.IsActive and node.IsAnchor then
			dist[idx] = 0
			table.insert(queue, idx)
		end
	end

	local iterations = 0
	while head <= #queue and iterations < MAX_BFS_ITER do
		iterations = iterations + 1
		local cur = queue[head]
		head = head + 1
		local curDist = dist[cur]
		local curNode = nodes[cur]
		if not curNode then continue end
		if curDist > maxRadius then continue end

		local curEdges = edges[cur]
		if not curEdges then continue end

		for i = 1, #curEdges do
			local e = curEdges[i]
			if active[e.WeldId] ~= nil then
				local tgt = nodes[e.Target]
				if tgt and tgt.IsActive then
					local edgeLen = (curNode.Position - tgt.Position).Magnitude
					local newDist = curDist + edgeLen
					if newDist <= maxRadius then
						local oldDist = dist[e.Target]
						if oldDist == nil or newDist < oldDist then
							dist[e.Target] = newDist
							table.insert(queue, e.Target)
						end
					end
				end
			end
		end
	end

	return dist
end

local function pillarBonus(distToAnchor: number): number
	return 1.0 + PILLAR_BONUS_K * math.exp(-distToAnchor * PILLAR_BONUS_DECAY)
end

local function stressOf(W: number, rHoriz: number, F_horiz: number, edge: Edge): (number, number)
	local A = edge.A_contact
	if A < 1e-6 then A = 1e-6 end
	local I = edge.I_contact
	if I < 1e-6 then I = 1e-6 end
	local c = math.sqrt(A) * 0.5
	local sigma_comp = W / A
	local sigma_bend = (W * rHoriz * c) / I
	local sigma_total = sigma_comp + sigma_bend
	local tau_cut = math.abs(F_horiz) / A
	return sigma_total, tau_cut
end

local function applyStress(graph: Graph, edge: Edge, sigma: number, tau: number, dt: number): boolean
	return graph:ApplySingleStress(edge, sigma, tau, dt)
end

function ForcePropagator.Propagate(
	graph: Graph,
	startIdx: number,
	initialForce: number,
	maxRadius: number,
	forceDecay: number?
): PropagateResult
	local decay = forceDecay or DEFAULT_DECAY
	local nodes = graph.Nodes
	local edges = graph.Edges
	local active = graph.ActiveWelds

	local brokenEdges: { [number]: boolean } = {}
	local impactsList: { ImpactInfo } = {}

	local startNode = nodes[startIdx]
	if not startNode or not startNode.IsActive or maxRadius <= 0 then
		return { brokenEdges = brokenEdges, impactsList = impactsList }
	end

	local anchorDist = computeAnchorDistances(graph, maxRadius * 2)

	local bestForce: { [number]: number } = { [startIdx] = initialForce }
	local stressedWelds: { [number]: boolean } = {}

	local queue: { { idx: number, force: number, dist: number } } = {
		{ idx = startIdx, force = initialForce, dist = 0 }
	}
	local head = 1
	local iterations = 0

	while head <= #queue and iterations < MAX_BFS_ITER do
		iterations = iterations + 1
		local cur = queue[head]
		head = head + 1

		local node = nodes[cur.idx]
		if not node or not node.IsActive then continue end
		if cur.dist >= maxRadius then continue end

		local curEdges = edges[cur.idx]
		if not curEdges then continue end

		local fromAtt = 1 - cur.dist / maxRadius

		for i = 1, #curEdges do
			local e = curEdges[i]
			if active[e.WeldId] == nil or stressedWelds[e.WeldId] then continue end

			local tgt = nodes[e.Target]
			if not tgt or not tgt.IsActive then continue end

			local edgeLen = (node.Position - tgt.Position).Magnitude
			local totalDist = cur.dist + edgeLen
			if totalDist > maxRadius then continue end

			local toAtt = 1 - totalDist / maxRadius
			local forceAtTarget = cur.force * decay * toAtt / fromAtt
			if forceAtTarget < MIN_FORCE_EPS then continue end
			if forceAtTarget <= (bestForce[e.Target] or 0) then continue end

			stressedWelds[e.WeldId] = true
			bestForce[e.Target] = forceAtTarget
			table.insert(impactsList, {
				idx = e.Target,
				force = forceAtTarget,
				dist = totalDist,
			})

			local dA = anchorDist[e.Target] or (maxRadius * 2)
			local bonus = pillarBonus(dA)
			local sigma, tau = stressOf(forceAtTarget, 0, forceAtTarget, e)

			local broke = applyStress(graph, e, sigma / bonus, tau / bonus, DEFAULT_DT)

			local nextForce = forceAtTarget
			if broke then
				brokenEdges[e.WeldId] = true
				nextForce = forceAtTarget * BROKEN_FORCE_KEEP
			end

			if nextForce >= MIN_FORCE_EPS then
				table.insert(queue, {
					idx = e.Target,
					force = nextForce,
					dist = totalDist,
				})
			end
		end
	end

	return { brokenEdges = brokenEdges, impactsList = impactsList }
end

function ForcePropagator.PropagateMulti(
	graph: Graph,
	seeds: { Seed },
	maxRadius: number,
	forceDecay: number?,
	opts: { DirectionalBias: number?, ImpulseDt: number? }?
): PropagateResult
	local decay = forceDecay or DEFAULT_DECAY
	local bias = (opts and opts.DirectionalBias) or 0.35
	local impulseDt = (opts and opts.ImpulseDt) or 1.0
	local nodes = graph.Nodes
	local edges = graph.Edges
	local active = graph.ActiveWelds

	local brokenEdges: { [number]: boolean } = {}
	local impactsList: { ImpactInfo } = {}

	local valid: { Seed } = {}
	local seedForce: { [number]: number } = {}
	for i = 1, #seeds do
		local s = seeds[i]
		local n = nodes[s.idx]
		if n and n.IsActive and s.force > MIN_FORCE_EPS then
			valid[#valid + 1] = s
			local old = seedForce[s.idx]
			if old == nil or s.force > old then
				seedForce[s.idx] = s.force
			end
		end
	end
	if #valid == 0 or maxRadius <= 0 then
		return { brokenEdges = brokenEdges, impactsList = impactsList }
	end
	table.sort(valid, function(a, b) return a.force > b.force end)

	local anchorLimit = maxRadius * 2 + 10
	local anchorDist = computeAnchorDistances(graph, anchorLimit)

	local bestForce: { [number]: number } = {}
	for idx, f in pairs(seedForce) do
		bestForce[idx] = f
	end

	local stressed: { [number]: boolean } = {}
	local queue: { any } = {}
	for i = 1, #valid do
		local s = valid[i]
		impactsList[#impactsList + 1] = { idx = s.idx, force = s.force, dist = 0 }
		queue[#queue + 1] = { idx = s.idx, force = s.force, dist = 0, dir = s.dir or DOWN, direct = true }
	end

	local head = 1
	local iterations = 0
	while head <= #queue and iterations < MAX_BFS_ITER do
		iterations += 1
		local cur = queue[head]
		head += 1

		local node = nodes[cur.idx]
		if not node or not node.IsActive then continue end

		local direct: boolean = cur.direct == true
		if not direct and cur.dist >= maxRadius then continue end

		local curEdges = edges[cur.idx]
		if not curEdges then continue end

		local dir: Vector3 = cur.dir

		for i = 1, #curEdges do
			local e = curEdges[i]
			if active[e.WeldId] == nil or stressed[e.WeldId] then continue end

			local tgt = nodes[e.Target]
			if not tgt or not tgt.IsActive then continue end

			local delta = tgt.Position - node.Position
			local edgeLen = delta.Magnitude
			if edgeLen < 1e-4 then edgeLen = 1e-4 end
			local u = delta / edgeLen
			local dirFactor = (1 - bias) + bias * math.max(0, dir:Dot(u))

			local fAt: number
			local totalDist: number
			if direct then
				fAt = cur.force
				local other = seedForce[e.Target]
				if other and other > fAt then fAt = other end
				totalDist = edgeLen
			else
				totalDist = cur.dist + edgeLen
				if totalDist > maxRadius then continue end
				local fromAtt = 1 - cur.dist / maxRadius
				local toAtt = 1 - totalDist / maxRadius
				fAt = cur.force * decay * toAtt / fromAtt * dirFactor
				if fAt < MIN_FORCE_EPS or fAt <= (bestForce[e.Target] or 0) then continue end
			end

			stressed[e.WeldId] = true

			local align = math.abs(dir:Dot(u))
			local shear = math.sqrt(math.max(0, 1 - align * align))
			local bonus = pillarBonus(anchorDist[e.Target] or anchorLimit)
			local sigma, tau = stressOf(
				fAt * (0.4 + 0.6 * align), edgeLen * 0.5 * shear, fAt * shear, e
			)
			local dt = if direct then impulseDt else impulseDt * 0.5
			local broke = applyStress(graph, e, sigma / bonus, tau / bonus, dt)
			if broke then
				brokenEdges[e.WeldId] = true
			end

			local nextForce: number
			local nextDist: number
			if direct then
				if seedForce[e.Target] then continue end
				local toAtt = 1 - edgeLen / maxRadius
				if toAtt <= 0 then continue end
				nextForce = fAt * decay * toAtt * dirFactor
				nextDist = edgeLen
			else
				nextForce = fAt
				nextDist = totalDist
			end
			if broke then
				nextForce *= BROKEN_FORCE_KEEP
			end

			if nextForce >= MIN_FORCE_EPS and nextForce > (bestForce[e.Target] or 0) then
				bestForce[e.Target] = nextForce
				impactsList[#impactsList + 1] = { idx = e.Target, force = nextForce, dist = nextDist }
				queue[#queue + 1] = { idx = e.Target, force = nextForce, dist = nextDist, dir = dir }
			end
		end
	end

	return { brokenEdges = brokenEdges, impactsList = impactsList }
end

function ForcePropagator.PropagateTension(
	graph: Graph,
	startIdx: number,
	force: number,
	radius: number
): PropagateResult
	local nodes = graph.Nodes
	local edges = graph.Edges
	local active = graph.ActiveWelds
	local fp = graph.Config.FP_SCALE
	local epsFixed = graph.Config.TOPO_EPS * fp

	local brokenEdges: { [number]: boolean } = {}
	local impactsList: { ImpactInfo } = {}

	local startNode = nodes[startIdx]
	if not startNode or not startNode.IsActive then
		return { brokenEdges = brokenEdges, impactsList = impactsList }
	end

	local startY = startNode.YFixed

	local affectedSet: { [number]: boolean } = { [startIdx] = true }
	local affected: { number } = { startIdx }
	local distMap: { [number]: number } = { [startIdx] = 0 }
	local queue: { number } = { startIdx }
	local head = 1
	local iterations = 0

	while head <= #queue and iterations < MAX_BFS_ITER do
		iterations = iterations + 1
		local cur = queue[head]
		head = head + 1
		local curNode = nodes[cur]
		if not curNode then continue end
		local curDist = distMap[cur] or 0

		local curEdges = edges[cur]
		if not curEdges then continue end

		for i = 1, #curEdges do
			local e = curEdges[i]
			if active[e.WeldId] ~= nil then
				local tgt = nodes[e.Target]
				if tgt and tgt.IsActive and not affectedSet[e.Target] then
					if tgt.YFixed >= startY - epsFixed then
						local edgeLen = (curNode.Position - tgt.Position).Magnitude
						local newDist = curDist + edgeLen
						if newDist <= radius then
							affectedSet[e.Target] = true
							distMap[e.Target] = newDist
							table.insert(affected, e.Target)
							table.insert(queue, e.Target)
						end
					end
				end
			end
		end
	end

	local totalMass = 0
	for i = 1, #affected do
		local n = nodes[affected[i]]
		if n and n.IsActive then
			totalMass = totalMass + n.Mass
		end
	end
	if totalMass < 1e-6 then totalMass = 1e-6 end

	table.sort(affected, function(a, b)
		local na = nodes[a]
		local nb = nodes[b]
		if na.YFixed ~= nb.YFixed then
			return na.YFixed > nb.YFixed
		end
		return a < b
	end)

	local cumMass: { [number]: number } = {}
	local running = 0
	for ai = 1, #affected do
		local n = nodes[affected[ai]]
		if n and n.IsActive then
			running = running + n.Mass
		end
		cumMass[affected[ai]] = running
	end

	for ai = 1, #affected do
		local idx = affected[ai]
		local node = nodes[idx]
		if not node or not node.IsActive then continue end

		table.insert(impactsList, {
			idx = idx,
			force = force * (node.Mass / totalMass),
			dist = distMap[idx] or 0,
		})

		local nodeEdges = edges[idx]
		if not nodeEdges then continue end

		for i = 1, #nodeEdges do
			local e = nodeEdges[i]
			if active[e.WeldId] ~= nil then
				local tgt = nodes[e.Target]
				if tgt and tgt.IsActive and affectedSet[e.Target] and tgt.YFixed > node.YFixed + epsFixed then
					local load = force * (cumMass[e.Target] / totalMass)

					local dx = node.Position.X - tgt.Position.X
					local dz = node.Position.Z - tgt.Position.Z
					local rHoriz = math.sqrt(dx * dx + dz * dz)

					local sigma, tau = stressOf(load, rHoriz, load * 0.1, e)

					if applyStress(graph, e, sigma, tau, DEFAULT_DT) then
						brokenEdges[e.WeldId] = true
					end
				end
			end
		end
	end

	return { brokenEdges = brokenEdges, impactsList = impactsList }
end

return ForcePropagator

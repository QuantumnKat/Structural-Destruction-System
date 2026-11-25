--!strict
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NeighborTracker   = require(ReplicatedStorage.Shared.Destruction.NeighborTracker)
local IslandActivator   = require(script.Parent.Parent.Structure.IslandActivator)
local DisconnectHandler = require(script.Parent.Parent.Structure.DisconnectHandler)

local ins = table.insert
local next_ = next
local typeOf = typeof

local SyncDisconnected = {}

local WHITELIST_REASONS = {
	["Hit"]          = true,
	["Collapse"]     = true,
	["Shatter"]      = true,
	["Impact"]       = true,
	["Chunk"]        = true,
	["StressBreak"]  = true,
	["SupportBreak"] = true,
}

local function destroyWeldsOn(part: BasePart)
	local children = part:GetChildren()
	for i = 1, #children do
		local c = children[i]
		if c:IsA("WeldConstraint") or c:IsA("Weld") then
			c:Destroy()
		end
	end
end

local function removeNeighborPair(part: BasePart, other: BasePart?, otherIdx: number?)
	if other and other.Parent and type(otherIdx) == "number" then
		NeighborTracker.RemoveNeighbor(other, (part:GetAttribute("PartIndex")))
	end
	if otherIdx ~= nil then
		NeighborTracker.RemoveNeighbor(part, otherIdx)
	end
end

function SyncDisconnected.SyncAndActivateDisconnected(
	graph: any,
	physicalPartMap: { [number]: BasePart },
	ActiveParts: { BasePart },
	outCollapse: { number },
	hitPartIndex: number,
	debrisList: { any },
	camFolder: Instance,
	replicationEvent: RemoteEvent?
): boolean
	local needsRebuild = false
	local nodes = graph.Nodes
	local edges = graph.Edges
	local activeWelds = graph.ActiveWelds

	local toProcess: { number } = {}
	for idx, node in pairs(nodes) do
		if not node.IsActive
			and idx ~= hitPartIndex
			and WHITELIST_REASONS[node.DeactivatedBy] == nil then
			ins(toProcess, idx)
		end
	end

	for i = 1, #toProcess do
		local idx = toProcess[i]
		local node = nodes[idx]
		local part = physicalPartMap[idx]
		if part and part.Parent and not part:GetAttribute("IsFalling") then
			destroyWeldsOn(part)

			local neighbors = NeighborTracker.GetNeighbors(part)
			if neighbors then
				local copy: { number } = {}
				for k = 1, #neighbors do
					copy[k] = neighbors[k]
				end
				for k = 1, #copy do
					local nid = copy[k]
					local np = physicalPartMap[nid]
					if np and np.Parent then
						NeighborTracker.RemoveNeighbor(np, idx)
					end
					NeighborTracker.RemoveNeighbor(part, nid)
				end
			end

			part:SetAttribute("_DeactivatedBy", node.DeactivatedBy)
			local needsRB = DisconnectHandler.HandleDisconnect(
				part, idx, graph, physicalPartMap, ActiveParts, outCollapse,
				debrisList, camFolder, replicationEvent, nil
			)
			if part.Parent then
				part:SetAttribute("_DeactivatedBy", nil)
			end
			if needsRB then
				needsRebuild = true
			end
		end
		task.wait()
	end

	for idx, part in pairs(physicalPartMap) do
		if part and part.Parent and not part:GetAttribute("IsFalling") then
			local children = part:GetChildren()
			for k = 1, #children do
				local c = children[k]
				if c:IsA("WeldConstraint") or c:IsA("Weld") then
					local p0 = c.Part0
					local p1 = c.Part1
					local other = nil
					if p0 == part then
						other = p1
					elseif p1 == part then
						other = p0
					end

					if other and other.Parent then
						local otherIdx = other:GetAttribute("PartIndex")
						if type(otherIdx) == "number" then
							local stillActive = false
							local edgesCur = edges[idx]
							if edgesCur then
								for e = 1, #edgesCur do
									local edge = edgesCur[e]
									if edge.Target == otherIdx and activeWelds[edge.WeldId] ~= nil then
										stillActive = true
										break
									end
								end
							end

							if not stillActive then
								c:Destroy()
								NeighborTracker.RemoveNeighbor(part, otherIdx)
								NeighborTracker.RemoveNeighbor(other, idx)
							end
						end
					end
				end
			end
		end
	end

	local reachable: { [number]: boolean } = {}
	local queue: { number } = {}
	local head = 1

	for idx, node in pairs(nodes) do
		if node.IsActive and node.IsAnchor then
			reachable[idx] = true
			ins(queue, idx)
		end
	end

	while head <= #queue do
		local cur = queue[head]
		head = head + 1
		local edgesCur = edges[cur]
		if edgesCur then
			for k = 1, #edgesCur do
				local edge = edgesCur[k]
				if activeWelds[edge.WeldId] ~= nil and not reachable[edge.Target] then
					local t = nodes[edge.Target]
					if t and t.IsActive then
						reachable[edge.Target] = true
						ins(queue, edge.Target)
					end
				end
			end
		end
	end

	local visited: { [number]: boolean } = {}

	for idx, node in pairs(nodes) do
		if node.IsActive and not reachable[idx] and not visited[idx] then
			local island: { BasePart } = {}
			local islandIdx: { number } = {}
			local bfsQueue: { number } = { idx }
			local bfsHead = 1
			visited[idx] = true

			while bfsHead <= #bfsQueue do
				local cur = bfsQueue[bfsHead]
				bfsHead = bfsHead + 1
				local curNode = nodes[cur]
				if curNode and curNode.IsActive then
					local p = physicalPartMap[cur]
					if p and p.Parent then
						ins(island, p)
						ins(islandIdx, cur)
					end
					local edgesCur = edges[cur]
					if edgesCur then
						for k = 1, #edgesCur do
							local edge = edgesCur[k]
							if activeWelds[edge.WeldId] ~= nil and not visited[edge.Target] then
								local t = nodes[edge.Target]
								if t and t.IsActive then
									visited[edge.Target] = true
									ins(bfsQueue, edge.Target)
								end
							end
						end
					end
				end
			end

			if #island > 0 then
				local needsRB = IslandActivator.ActivateIsland(
					island, physicalPartMap, graph, ActiveParts,
					outCollapse, debrisList, camFolder, replicationEvent
				)
				if needsRB then
					needsRebuild = true
				end
			end
		end
	end

	return needsRebuild
end

return SyncDisconnected

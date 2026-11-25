--!strict
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NeighborTracker   = require(ReplicatedStorage.Shared.Destruction.NeighborTracker)

local ins = table.insert

local WeldTree = {}

local function getNextWeldId(graph: any): number
	if not graph._NextWeldId then
		graph._NextWeldId = 1_000_000
	end
	local n = graph._NextWeldId
	graph._NextWeldId = n + 1
	return n
end

function WeldTree.ClearWeldsOnParts(parts: { BasePart })
	for i = 1, #parts do
		local p = parts[i]
		if p and p.Parent then
			local children = p:GetChildren()
			for j = 1, #children do
				local c = children[j]
				if c:IsA("WeldConstraint") or c:IsA("Weld") then
					c:Destroy()
				end
			end
		end
	end
end

function WeldTree.WeldIslandTree(
	graph: any,
	island: { BasePart },
	physicalPartMap: { [number]: BasePart },
	islandSet: { [number]: boolean }
)
	if #island < 2 then
		return
	end

	local root = island[1]
	local rootIdx = root:GetAttribute("PartIndex")
	if type(rootIdx) ~= "number" then
		return
	end

	local inTree: { [number]: boolean } = { [rootIdx] = true }
	local queue: { BasePart } = { root }
	local head = 1

	while head <= #queue do
		local cur = queue[head]
		head = head + 1

		if not cur or not cur.Parent then continue end

		local curIdx = cur:GetAttribute("PartIndex")
		if type(curIdx) ~= "number" then continue end

		local curFalling = cur:GetAttribute("IsFalling") == true
		local neighbors = NeighborTracker.GetNeighbors(cur)
		if not neighbors then continue end

		for i = 1, #neighbors do
			local nid = neighbors[i]
			if islandSet[nid] and not inTree[nid] then
				local np = physicalPartMap[nid]
				if np and np.Parent then
					inTree[nid] = true
					local npFalling = np:GetAttribute("IsFalling") == true

					if curFalling == npFalling then
						if not graph:GetEdgeBetween(curIdx, nid) then
							local w = Instance.new("WeldConstraint")
							w.Part0 = cur
							w.Part1 = np
							w.Parent = cur
							if graph then
								graph:AddWeld(getNextWeldId(graph), curIdx, nid, w)
							end
						end
					end
					ins(queue, np)
				end
			end
		end
	end
end

return WeldTree

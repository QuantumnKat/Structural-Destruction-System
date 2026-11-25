--!strict
--!native

local ObjectConf        = require(script.Parent.Parent.Parent.Objects.ObjectConf)
local WeldTree          = require(script.Parent.Parent.Structure.WeldTree)
local DisconnectHandler = require(script.Parent.Parent.Structure.DisconnectHandler)
local ForcePropagator   = require(script.Parent.Parent.Structure.ForcePropagator)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NeighborTracker   = require(ReplicatedStorage.Shared.Destruction.NeighborTracker)

local mathmax = math.max

local IslandActivator = {}

local TENSION_RADIUS = 20
local SHATTER_MASS_DEFAULT = 50
local YIELD_EVERY = 20

local function getShatterMassThreshold(): number
	local Constants = nil
	local ok, res = pcall(function()
		return require(script.Parent.Parent.Support.Constants)
	end)
	if ok and type(res) == "table" then
		Constants = res
	end
	if Constants and type(Constants.SHATTER_MASS_THRESHOLD) == "number" then
		return Constants.SHATTER_MASS_THRESHOLD
	end
	return SHATTER_MASS_DEFAULT
end

local function getMatRule(part: BasePart): any
	local rule = part:GetAttribute("MaterialRule")
	if type(rule) == "table" then
		return rule
	end
	if ObjectConf and ObjectConf.GetMaterialRule then
		local ok, res = pcall(function()
			return ObjectConf.GetMaterialRule(part.Material)
		end)
		if ok and type(res) == "table" then
			return res
		end
	end
	return {}
end

function IslandActivator.ActivateIsland(
	island: { BasePart },
	physicalPartMap: { [number]: BasePart },
	graph: any,
	ActiveParts: { BasePart },
	outCollapse: { number },
	debrisList: { any },
	camFolder: Instance,
	replicationEvent: RemoteEvent?
): boolean
	if not island or #island == 0 then
		return false
	end

	local islandIdxSet: { [number]: boolean } = {}
	local totalIslandMass = 0

	for i = 1, #island do
		local p = island[i]
		if p and p.Parent then
			local idx = p:GetAttribute("PartIndex")
			if type(idx) == "number" then
				islandIdxSet[idx] = true
			end
			if not p:GetAttribute("IsFalling") then
				local m = p:GetMass()
				if m <= 0 then
					local s = p.Size
					m = s.X * s.Y * s.Z
					if m <= 0 then m = 1 end
				end
				totalIslandMass = totalIslandMass + m
			end
		end
	end

	if next(islandIdxSet) == nil then
		return false
	end

	--[[local anyAnchored = false
	for i = 1, #island do
		local p = island[i]
		if p and p.Parent and p.Anchored then
			anyAnchored = true
			break
		end
	end
	if anyAnchored then
		return false
	end]]--

	if totalIslandMass < 1 then
		totalIslandMass = 1
	end

	for i = 1, #island do
		local p = island[i]
		if not p or not p.Parent then continue end

		local neighbors = NeighborTracker.GetNeighbors(p)
		if not neighbors then continue end

		local neighborCopy: { number } = {}
		for k = 1, #neighbors do
			neighborCopy[k] = neighbors[k]
		end

		for k = 1, #neighborCopy do
			local nid = neighborCopy[k]
			if not islandIdxSet[nid] then
				local result = ForcePropagator.PropagateTension(
					graph, nid, totalIslandMass, TENSION_RADIUS
				)
				if result and result.brokenEdges then
					for weldId, _ in pairs(result.brokenEdges) do
						if graph.ActiveWelds[weldId] ~= nil then
							graph:RemoveWeld(weldId)
						end
					end
				end
			end
		end
	end

	local shatterThreshold = getShatterMassThreshold()
	local detachParts: { BasePart } = {}

	for i = 1, #island do
		local p = island[i]
		if not p or not p.Parent then continue end

		local matRule = getMatRule(p)
		local mode = p:GetAttribute("OnDisconnect")
		if type(mode) ~= "string" then
			mode = matRule.OnDisconnect
		end
		if type(mode) ~= "string" then
			mode = "Detach"
		end

		local mass = p:GetMass()
		if mass <= 0 then
			local s = p.Size
			mass = s.X * s.Y * s.Z
			if mass <= 0 then mass = 1 end
		end

		if mode == "Detach" and mass > shatterThreshold then
			mode = "Shatter"
		end

		if mode == "Detach" then
			table.insert(detachParts, p)
		end
	end

	if #detachParts > 0 then
		WeldTree.ClearWeldsOnParts(detachParts)
		WeldTree.WeldIslandTree(graph, detachParts, physicalPartMap, islandIdxSet)
	end

	local needsRebuild = false
	local processed = 0

	for i = 1, #island do
		local p = island[i]
		if not p or not p.Parent then continue end
		if p:GetAttribute("IsFalling") then continue end

		local idx = p:GetAttribute("PartIndex")
		if type(idx) ~= "number" then continue end

		local needsRB = DisconnectHandler.HandleDisconnect(
			p, idx, graph, physicalPartMap, ActiveParts, outCollapse,
			debrisList, camFolder, replicationEvent, nil
		)
		if needsRB then
			needsRebuild = true
		end

		processed = processed + 1
		if processed % YIELD_EVERY == 0 then
			task.wait()
		end
	end

	return needsRebuild
end

return IslandActivator

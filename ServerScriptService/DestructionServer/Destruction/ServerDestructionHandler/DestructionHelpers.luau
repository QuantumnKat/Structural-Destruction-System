--!strict
--!native

return function(deps: any)
	local ins, osclock, typeOf = table.insert, os.clock, typeof
	local ObjectConf = deps.ObjectConf
	local ObjectManager = deps.ObjectManager
	local NeighborTracker = deps.NeighborTracker
	local ForcePropagator = deps.ForcePropagator
	local PhysicsHelpers = deps.PhysicsHelpers
	local Constants = deps.Constants
	local MapSerializer = deps.MapSerializer
	local WAKE_RADIUS = deps.WAKE_RADIUS
	local DEBUG = deps.DEBUG

	local ATTRIBUTION_TTL = 6.0

	local function stampPartAttribution(part: BasePart?, attackerUserId: any, attributionDamage: any, nowClock: number?)
		if not part or not part.Parent or typeOf(attackerUserId) ~= "number" or attackerUserId <= 0 then
			return
		end
		part:SetAttribute("AttackerUserId", attackerUserId)
		if typeOf(attributionDamage) == "number" then
			part:SetAttribute("AttributionDamage", attributionDamage)
		end
		part:SetAttribute("AttributionExpire", workspace:GetServerTimeNow() + ATTRIBUTION_TTL)
		if nowClock then
			part:SetAttribute("_SpawnTime", nowClock)
		end
	end

	local function stampRange(ActiveParts: { BasePart }, fromIdx: number, attackerUserId: any, attributionDamage: any)
		if typeOf(attackerUserId) ~= "number" or attackerUserId <= 0 then
			return
		end
		for i = fromIdx, #ActiveParts do
			stampPartAttribution(ActiveParts[i], attackerUserId, attributionDamage, nil)
		end
	end

	local function stampDebrisList(debrisList: { any }?, attackerUserId: any, attributionDamage: any)
		if not debrisList or typeOf(attackerUserId) ~= "number" or attackerUserId <= 0 then
			return
		end
		for i = 1, #debrisList do
			local entry = debrisList[i]
			if typeOf(entry) == "Instance" and entry:IsA("BasePart") then
				stampPartAttribution(entry, attackerUserId, attributionDamage, nil)
			elseif typeOf(entry) == "table" then
				local p = entry.part or entry.Part or entry.instance
				if typeOf(p) == "Instance" and p:IsA("BasePart") then
					stampPartAttribution(p, attackerUserId, attributionDamage, nil)
				end
			end
		end
	end

	local function stampCollapsedParts(
		toCollapse: { number },
		physicalPartMap: { [number]: BasePart },
		attackerUserId: any,
		attributionDamage: any
	)
		if typeOf(attackerUserId) ~= "number" or attackerUserId <= 0 then
			return
		end
		for i = 1, #toCollapse do
			local part = physicalPartMap[toCollapse[i]]
			if part and part.Parent then
				stampPartAttribution(part, attackerUserId, attributionDamage, nil)
			end
		end
	end

	local function resolveMapFolders(): (Instance?, Instance?)
		local camFolder = workspace:FindFirstChild("Camera")
		if not camFolder then
			return nil, nil
		end
		return camFolder, camFolder:FindFirstChild("Map")
	end

	local EMPTY_RULE: any = {}
	local matRuleCache: { [Enum.Material]: any } = {}

	local function getMatRule(part: BasePart): any
		local mat = part.Material
		local cached = matRuleCache[mat]
		if cached then return cached end

		local rule: any = EMPTY_RULE
		if ObjectConf and ObjectConf.GetMaterialRule then
			local ok, res = pcall(ObjectConf.GetMaterialRule, mat)
			if ok and typeOf(res) == "table" then
				rule = res
			end
		end
		matRuleCache[mat] = rule
		return rule
	end

	local function canDestroy(part: BasePart): boolean
		if not part or not part.Parent then
			return false
		end
		if part:GetAttribute("IsDestructible") == false then
			return false
		end
		local rule = getMatRule(part)
		if rule.Destroyable == false then
			return false
		end
		return true
	end

	local function resolveShatterRule(part: BasePart, matRule: any): any
		local clone = {}
		if typeOf(matRule) == "table" then
			for k, v in pairs(matRule) do
				clone[k] = v
			end
		end
		local ap = part:GetAttribute("ShatterAirPercent")
		if typeOf(ap) == "number" then
			clone.ShatterAirPercent = ap
		elseif typeOf(clone.ShatterAirPercent) ~= "number" then
			clone.ShatterAirPercent = 0.5
		end
		local md = part:GetAttribute("MaxDebrisPerPart")
		if typeOf(md) == "number" then
			clone.MaxDebrisPerPart = md
		elseif typeOf(clone.MaxDebrisPerPart) ~= "number" then
			clone.MaxDebrisPerPart = 64
		end
		return clone
	end

	local function ensureActive(ActiveParts: { BasePart }, part: BasePart)
		for i = 1, #ActiveParts do
			if ActiveParts[i] == part then return end
		end
		ins(ActiveParts, part)
	end

	local function removeActive(ActiveParts: { BasePart }, part: BasePart)
		for i = #ActiveParts, 1, -1 do
			if ActiveParts[i] == part then
				local last = #ActiveParts
				ActiveParts[i] = ActiveParts[last]
				ActiveParts[last] = nil
			end
		end
	end

	local function copyNeighbors(part: BasePart): { number }?
		local neighbors = NeighborTracker.GetNeighbors(part)
		if not neighbors then return nil end
		local copy: { number } = {}
		for i = 1, #neighbors do
			copy[i] = neighbors[i]
		end
		return copy
	end

	local function clearNeighbors(part: BasePart, physicalPartMap: { [number]: BasePart })
		local idx = part:GetAttribute("PartIndex")
		if typeOf(idx) ~= "number" then return end
		local copy = copyNeighbors(part)
		if not copy then return end
		for i = 1, #copy do
			local nid = copy[i]
			local np = physicalPartMap[nid]
			if np and np.Parent then
				NeighborTracker.RemoveNeighbor(np, idx)
			end
			NeighborTracker.RemoveNeighbor(part, nid)
		end
	end

	local function removeOldNeighbors(
		neighborCopy: { number }?,
		idx: number,
		physicalPartMap: { [number]: BasePart }
	)
		if not neighborCopy then return end
		for i = 1, #neighborCopy do
			local np = physicalPartMap[neighborCopy[i]]
			if np and np.Parent then
				NeighborTracker.RemoveNeighbor(np, idx)
			end
		end
	end

	local function propagate(graph: any, idx: number, force: number, radius: number, falloff: number): any
		local a: any, _b: any = ForcePropagator.Propagate(graph, idx, force, radius, falloff)
		if typeOf(a) == "table" and a.brokenEdges ~= nil then
			return a.brokenEdges
		end
		return a
	end

	local function breakWelds(graph: any, edges: any)
		if typeOf(edges) ~= "table" then return end
		for weldId, _ in pairs(edges) do
			if graph.ActiveWelds[weldId] ~= nil then
				graph:RemoveWeld(weldId)
			end
		end
	end

	local function wakeAround(part: BasePart, tag: string, force: number?, attackerUserId: number?)
		local woke = 0
		if part:GetAttribute("IsSleeping") then
			if ObjectManager.WakePart(part, attackerUserId) then woke += 1 end
		end
		woke += ObjectManager.WakeNearby(part.Position, WAKE_RADIUS, attackerUserId)
		if DEBUG and woke > 0 then
			print(("[%s] Woke %d sleeping parts (force=%s)"):format(tag, woke, tostring(force)))
		end
	end

	local function detachPart(
		part: BasePart,
		idx: number,
		matRule: any,
		ActiveParts: { BasePart },
		replicationEvent: RemoteEvent?,
		collapseOut: { number }?,
		attackerUserId: any?,
		attributionDamage: any?
	)
		part.Anchored = false
		part:SetAttribute("IsSleeping", false)
		pcall(function()
			part:SetNetworkOwner(nil)
		end)
		PhysicsHelpers.ApplyFallingPhysics(part, matRule)
		part:SetAttribute("IsFalling", true)
		part:SetAttribute("ObjectId", idx + Constants.FALLING_ID_OFFSET)
		part:SetAttribute("_SpawnTime", osclock())
		stampPartAttribution(part, attackerUserId, attributionDamage, nil)
		ensureActive(ActiveParts, part)

		if collapseOut then
			ins(collapseOut, idx)
		elseif replicationEvent then
			replicationEvent:FireAllClients("COLLAPSE_PARTS", { idx })
		end
	end

	local function fireDebris(replicationEvent: RemoteEvent?, debrisList: { any })
		if not replicationEvent or #debrisList == 0 then return end
		local serialized
		if MapSerializer.SerializeDebris then
			serialized = MapSerializer.SerializeDebris(debrisList)
		elseif MapSerializer.Serialize then
			serialized = MapSerializer.Serialize(debrisList)
		end
		if serialized then
			replicationEvent:FireAllClients("CREATE_DEBRIS", serialized)
		end
	end

	return {
		resolveMapFolders = resolveMapFolders,
		getMatRule = getMatRule,
		canDestroy = canDestroy,
		resolveShatterRule = resolveShatterRule,
		ensureActive = ensureActive,
		removeActive = removeActive,
		copyNeighbors = copyNeighbors,
		clearNeighbors = clearNeighbors,
		removeOldNeighbors = removeOldNeighbors,
		propagate = propagate,
		breakWelds = breakWelds,
		wakeAround = wakeAround,
		detachPart = detachPart,
		fireDebris = fireDebris,
		stampPartAttribution = stampPartAttribution,
		stampRange = stampRange,
		stampDebrisList = stampDebrisList,
		stampCollapsedParts = stampCollapsedParts,
	}
end
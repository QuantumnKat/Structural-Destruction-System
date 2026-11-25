--!strict
--!native

return function(ServerDestructionHandler: any, deps: any)
	local ins, mathmax, mathclamp, typeOf = table.insert, math.max, math.clamp, typeof
	local PartIndexMap = deps.PartIndexMap
	local ChunkBreaker = deps.ChunkBreaker
	local Shatter = deps.Shatter
	local SyncDisconnected = deps.SyncDisconnected
	local FragmentManager = deps.FragmentManager
	local Thrust = deps.Thrust
	local ForcePropagator = deps.ForcePropagator
	local HitShapeMod = deps.HitShapeMod
	local ObjectManager = deps.ObjectManager
	local PROPAGATE_RADIUS = deps.PROPAGATE_RADIUS
	local WAKE_RADIUS = deps.WAKE_RADIUS
	local DEBUG = deps.DEBUG
	local resolveMapFolders = deps.Helpers.resolveMapFolders
	local getMatRule = deps.Helpers.getMatRule
	local canDestroy = deps.Helpers.canDestroy
	local resolveShatterRule = deps.Helpers.resolveShatterRule
	local removeActive = deps.Helpers.removeActive
	local copyNeighbors = deps.Helpers.copyNeighbors
	local clearNeighbors = deps.Helpers.clearNeighbors
	local removeOldNeighbors = deps.Helpers.removeOldNeighbors
	local breakWelds = deps.Helpers.breakWelds
	local detachPart = deps.Helpers.detachPart
	local fireDebris = deps.Helpers.fireDebris
	local stampDebrisList = deps.Helpers.stampDebrisList
	local stampCollapsedParts = deps.Helpers.stampCollapsedParts

	local function getClosestPointOnPart(part: BasePart, worldPos: Vector3): Vector3
		local localPos = part.CFrame:PointToObjectSpace(worldPos)
		local half = part.Size * 0.5
		local clamped = Vector3.new(
			mathclamp(localPos.X, -half.X, half.X),
			mathclamp(localPos.Y, -half.Y, half.Y),
			mathclamp(localPos.Z, -half.Z, half.Z)
		)
		return part.CFrame:PointToWorldSpace(clamped)
	end

	local function applyDirectDamage(
		hits: { any },
		graph: any,
		physicalPartMap: { [number]: BasePart },
		camFolder: Instance,
		ActiveParts: { BasePart },
		debrisList: { any },
		replicationEvent: RemoteEvent?,
		impactCenter: Vector3,
		collapseOut: { number },
		maxBreaks: number,
		attackerUserId: any?,
		attributionDamage: any?
	): boolean
		local needsRebuild = false
		local done = 0

		for i = 1, #hits do
			if done >= maxBreaks then break end
			local h = hits[i]
			local idx: number = h.idx
			local part = physicalPartMap[idx]
			if not part or not part.Parent then continue end
			if part:GetAttribute("IsFalling") then continue end
			if not canDestroy(part) then continue end

			local rule = getMatRule(part)
			local hpAttr = part:GetAttribute("HP")
			local hp: number = if typeOf(hpAttr) == "number" then hpAttr else 100
			local force: number = h.force
			local minForce = mathmax(rule.MinImpactForce or 0, rule.Hardness or 0)
			if force < hp * 0.05 or force < minForce then continue end

			local mode: any = part:GetAttribute("OnDisconnect")
			if typeOf(mode) ~= "string" then mode = rule.OnDisconnect end
			if typeOf(mode) ~= "string" then mode = "Auto" end
			if mode == "Ignore" then continue end
			if mode == "Detach" and force >= hp * 2 then mode = "Break" end

			local point: Vector3 = h.point or impactCenter
			local carvePoint = getClosestPointOnPart(part, point)
			local ratio = mathclamp(force / hp, 0.2, 2.0)
			local carveRadius = (rule.BreakRadius or 4) * ratio

			local neighborCopy = copyNeighbors(part)
			local destroyed = false

			if mode == "Detach" then
				clearNeighbors(part, physicalPartMap)
				detachPart(part, idx, rule, ActiveParts, replicationEvent, collapseOut, attackerUserId, attributionDamage)
				graph:DeactivateNode(idx, "Impact")
				done += 1
				continue
			end

			local doShatter = (mode == "Shatter") or (mode == "Auto" and force >= hp)
			if doShatter then
				Shatter.ShatterPart(
					part, resolveShatterRule(part, rule), "Shatter",
					carvePoint, carveRadius, camFolder, ActiveParts, debrisList
				)
				part:Destroy()
				physicalPartMap[idx] = nil
				graph:DeactivateNode(idx, "Shatter")
				destroyed = true
			else
				local d, rb = ChunkBreaker.BreakChunk(
					part, idx, carvePoint, carveRadius, impactCenter, force,
					graph, physicalPartMap, camFolder, ActiveParts,
					debrisList, replicationEvent, "Carve", nil, false
				)
				destroyed = d == true
				if rb then needsRebuild = true end
			end

			if destroyed then
				if replicationEvent then
					replicationEvent:FireAllClients("DESTROY_PART", idx)
				end
				removeOldNeighbors(neighborCopy, idx, physicalPartMap)
				removeActive(ActiveParts, part)
			end
			done += 1
		end

		return needsRebuild
	end

	function ServerDestructionHandler.HitShape(
		graph: any,
		shape: any,
		force: number,
		replicationEvent: RemoteEvent?,
		ActiveParts: { BasePart },
		opts: any?
	): boolean
		local o: any = opts or {}
		local camFolder, mapFolder = resolveMapFolders()
		if not camFolder then return false end

		local physicalPartMap = PartIndexMap.Build(mapFolder or camFolder)
		local mult: number = o.ForceMultiplier or 3.0
		local exclude: { [number]: boolean }? = o.ExcludeIdx
		local attackerUid = o.AttackerUserId
		local attrDmg = if o.AttributionDamage ~= nil then o.AttributionDamage else (force * mult)

		local raw = HitShapeMod.Query(graph, shape, force)
		local hits: { any } = {}
		for i = 1, #raw do
			local h = raw[i]
			local p = physicalPartMap[h.idx]
			if p and p.Parent and not p:GetAttribute("IsFalling") and not (exclude and exclude[h.idx]) then
				h.force = h.force * mult
				hits[#hits + 1] = h
			end
		end
		FragmentManager.LogHit(shape, force)
		if o.HitDebris ~= false then
			FragmentManager.HitFragments(shape, force * mult, {
				ExcludeIds = o.ExcludeIds,
				ExcludeFragmentId = o.ExcludeFragmentId,
			})
		end

		if #hits == 0 then return false end

		local center: Vector3 = shape.CFrame.Position
		local wakeRadius = mathmax(WAKE_RADIUS, HitShapeMod.BoundingRadius(shape))
		local woke = ObjectManager.WakeNearby(center, wakeRadius)
		if DEBUG and woke > 0 then
			print(("[HitShape] Woke %d parts"):format(woke))
		end

		local seeds: { any } = table.create(#hits)
		for i = 1, #hits do
			seeds[i] = { idx = hits[i].idx, force = hits[i].force, dir = hits[i].dir }
		end
		local result = ForcePropagator.PropagateMulti(
			graph, seeds, o.PropagateRadius or PROPAGATE_RADIUS, o.Decay or 0.4,
			{ DirectionalBias = o.DirectionalBias, ImpulseDt = o.ImpulseDt }
		)
		breakWelds(graph, result.brokenEdges)

		local debrisList: { any } = {}
		local collapseOut: { number } = {}
		local needsRebuild = applyDirectDamage(
			hits,
			graph,
			physicalPartMap,
			camFolder,
			ActiveParts,
			debrisList,
			replicationEvent,
			center,
			collapseOut,
			o.MaxDirectBreaks or 24,
			attackerUid,
			attrDmg
		)

		if o.Secondary == true then
			local isSeed: { [number]: boolean } = {}
			for i = 1, #hits do isSeed[hits[i].idx] = true end
			local secondary: { any } = {}
			for _, im in ipairs(result.impactsList) do
				if not isSeed[im.idx] then
					secondary[#secondary + 1] = { idx = im.idx, force = im.force, point = center }
				end
			end
			table.sort(secondary, function(a, b) return a.force > b.force end)
			local rb = applyDirectDamage(
				secondary,
				graph,
				physicalPartMap,
				camFolder,
				ActiveParts,
				debrisList,
				replicationEvent,
				center,
				collapseOut,
				o.MaxSecondary or 8,
				attackerUid,
				attrDmg
			)
			if rb then needsRebuild = true end
		end

		local toCollapse: { number } = {}
		local syncNeeds = SyncDisconnected.SyncAndActivateDisconnected(
			graph, physicalPartMap, ActiveParts, toCollapse, -1,
			debrisList, camFolder, replicationEvent
		)
		if syncNeeds then needsRebuild = true end

		stampCollapsedParts(toCollapse, physicalPartMap, attackerUid, attrDmg)
		stampDebrisList(debrisList, attackerUid, attrDmg)

		for i = 1, #collapseOut do
			ins(toCollapse, collapseOut[i])
		end

		FragmentManager.PlanFragments(toCollapse, physicalPartMap, {
			Force = force * mult,
			Center = center,
			Impacts = result.impactsList,
			Hits = hits,
			Shape = shape,
		})
		Thrust.Apply(toCollapse, physicalPartMap, { Force = force * mult, Center = center, Shape = shape })

		if replicationEvent then
			if #toCollapse > 0 then
				replicationEvent:FireAllClients("COLLAPSE_PARTS", toCollapse)
			end
			fireDebris(replicationEvent, debrisList)
		end

		return needsRebuild
	end
end
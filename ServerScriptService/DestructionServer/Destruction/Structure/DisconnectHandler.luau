--!strict
--!native

local ObjectConf     = require(script.Parent.Parent.Parent.Objects.ObjectConf)
local PhysicsHelpers = require(script.Parent.Parent.Support.PhysicsHelpers)
local Shatter        = require(script.Parent.Parent.Fragments.Shatter)
local ChunkBreaker   = require(script.Parent.Parent.Fragments.ChunkBreaker)
local Constants      = require(script.Parent.Parent.Support.Constants)

local osclock = os.clock
local mathmax = math.max
local typeOf  = typeof

local DisconnectHandler = {}

local function resolveMode(part: BasePart, matRule: any): string
	local attr = part:GetAttribute("OnDisconnect")
	if typeOf(attr) == "string" then
		return attr
	end
	if matRule and typeOf(matRule.OnDisconnect) == "string" then
		return matRule.OnDisconnect
	end
	return "Detach"
end

local function resolveRadius(part: BasePart, matRule: any): number
	local attr = part:GetAttribute("BreakRadius")
	if typeOf(attr) == "number" then
		return attr
	end
	if matRule and typeOf(matRule.BreakRadius) == "number" then
		return matRule.BreakRadius
	end
	return 4
end

local function getMatRule(part: BasePart): any
	if ObjectConf and ObjectConf.GetMaterialRule then
		local ok, res = pcall(ObjectConf.GetMaterialRule, part.Material)
		if ok and typeOf(res) == "table" then
			return res
		end
	end
	return {}
end

local function getShatterMassThreshold(): number
	local c = Constants
	if c and typeOf(c.SHATTER_MASS_THRESHOLD) == "number" then
		return c.SHATTER_MASS_THRESHOLD
	end
	return 50
end

local function ensureActive(ActiveParts: { BasePart }, part: BasePart)
	for i = 1, #ActiveParts do
		if ActiveParts[i] == part then return end
	end
	table.insert(ActiveParts, part)
end

function DisconnectHandler.HandleDisconnect(
	part: BasePart,
	idx: number,
	graph: any,
	physicalPartMap: { [number]: BasePart },
	ActiveParts: { BasePart },
	outCollapse: { number },
	debrisList: { any },
	camFolder: Instance,
	replicationEvent: RemoteEvent?,
	attackerPart: BasePart?
): boolean
	if not part or not part.Parent then
		return false
	end

	if part:GetAttribute("IsDestructible") == false then
		return false
	end

	local matRule = getMatRule(part)
	if matRule.Destroyable == false then
		return false
	end

	local onDisconnect = resolveMode(part, matRule)

	local deactivatedBy = part:GetAttribute("_DeactivatedBy")
	local forcedBreak = (deactivatedBy == "StressBreak" or deactivatedBy == "SupportBreak")
	if forcedBreak then
		onDisconnect = "Break"
	end

	local mass = part:GetMass()
	if mass <= 0 then
		local size = part.Size
		mass = size.X * size.Y * size.Z
		if mass <= 0 then mass = 1 end
	end

	local shatterThreshold = getShatterMassThreshold()
	if (onDisconnect == "Auto" or onDisconnect == "Detach") and mass > shatterThreshold then
		onDisconnect = "Break"
	end

	if onDisconnect == "Ignore" then
		return false
	end

	local needsRebuild = false

	if onDisconnect == "Detach" then
		part.Anchored = false
		part:SetAttribute("IsSleeping", false)
		pcall(function()
			part:SetNetworkOwner(nil)
		end)
		PhysicsHelpers.ApplyFallingPhysics(part, matRule)
		part:SetAttribute("IsFalling", true)
		part:SetAttribute("ObjectId", idx + Constants.FALLING_ID_OFFSET)
		part:SetAttribute("_SpawnTime", osclock())

		ensureActive(ActiveParts, part)
		table.insert(outCollapse, idx)
		return false
	end

	if onDisconnect == "Break" then
		local mode = "Carve"
		if forcedBreak or mass > shatterThreshold then
			mode = "Fracture"
		end

		local impactForce = part:GetAttribute("_LastImpactForce")
		if typeOf(impactForce) ~= "number" or impactForce <= 0 then
			local gravity = 196.2
			if workspace then
				gravity = workspace.Gravity
			end
			impactForce = mathmax(500, mass * gravity * 3)
		end

		local carveRadius = resolveRadius(part, matRule)
		local center = part.Position

		local destroyed, needsRB = ChunkBreaker.BreakChunk(
			part, idx, center, carveRadius, center, impactForce,
			graph, physicalPartMap, camFolder, ActiveParts, debrisList,
			replicationEvent, mode, nil, false, attackerPart
		)

		needsRebuild = needsRebuild or (needsRB == true)

		if destroyed then
			table.insert(outCollapse, idx)
			if replicationEvent then
				replicationEvent:FireAllClients("DESTROY_PART", idx)
			end
		end

		return needsRebuild
	end

	local carveRadius = resolveRadius(part, matRule)
	local impactForce = mathmax(500, mass * (workspace.Gravity or 196.2) * 3)

	local destroyed, needsRB = ChunkBreaker.BreakChunk(
		part, idx, part.Position, carveRadius, part.Position, impactForce,
		graph, physicalPartMap, camFolder, ActiveParts, debrisList,
		replicationEvent, "Shatter", nil, false, attackerPart
	)

	needsRebuild = needsRebuild or (needsRB == true)

	if destroyed then
		physicalPartMap[idx] = nil
		if replicationEvent then
			replicationEvent:FireAllClients("DESTROY_PART", idx)
		end
	end

	return needsRebuild
end

return DisconnectHandler

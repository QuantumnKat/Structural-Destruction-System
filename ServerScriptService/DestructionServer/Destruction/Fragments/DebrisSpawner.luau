--!strict
--!native

local ObjectManager  = require(script.Parent.Parent.Parent.Objects.ObjectManager)
local Constants      = require(script.Parent.Parent.Support.Constants)
local PhysicsHelpers = require(script.Parent.Parent.Support.PhysicsHelpers)
local PartIds        = require(script.Parent.Parent.Identity.PartIds)

local ins        = table.insert
local mathrand   = math.random
local osclock    = os.clock
local Vector3new = Vector3.new

local DebrisSpawner = {}

function DebrisSpawner.SpawnFromBoxes(
	boxes: { any },
	sourcePart: BasePart,
	matRule: any,
	impactCenter: Vector3,
	camFolder: Instance,
	ActiveParts: { BasePart },
	debrisList: { any }
): { BasePart }
	local count = #boxes
	local spawned: { BasePart } = {}
	if count == 0 then return spawned end

	local impulseMul = matRule and matRule.ImpulseMultiplier or 1.0
	local angMul     = matRule and matRule.AngularMultiplier or 1.0
	local minImpulse = Constants.MIN_IMPULSE
	local maxImpulse = Constants.MAX_IMPULSE
	local upImpulse  = Constants.UP_IMPULSE
	local maxAngular = Constants.MAX_ANGULAR

	for i = 1, count do
		local box = boxes[i]
		if not box then continue end

		local dPart = ObjectManager.Acquire()
		if not dPart then break end

		local cf: CFrame = box.CFrame or CFrame.new(box.Pos or impactCenter)
		local pos: Vector3 = box.Pos or cf.Position
		local size: Vector3 = box.Size or dPart.Size

		dPart.Size = size
		dPart.CFrame = cf

		dPart.Color = box.Color or (sourcePart and sourcePart.Color) or dPart.Color
		dPart.Material = box.Material or (sourcePart and sourcePart.Material) or dPart.Material
		dPart.Transparency = 0
		dPart.Reflectance = 0

		PhysicsHelpers.ApplyDebrisPhysics(dPart, matRule)

		dPart.Massless = false
		dPart.Anchored = false
		dPart.CanCollide = true
		dPart.CanQuery = true
		dPart.CanTouch = false
		dPart.CollisionGroup = "Debris"

		local objectId = PartIds.NewDebrisId()
		dPart:SetAttribute("ObjectId", objectId)
		dPart:SetAttribute("_SpawnTime", osclock())
		dPart:SetAttribute("IsSleeping", false)
		dPart:SetAttribute("FragmentId", nil)
		dPart:SetAttribute("FragmentRoot", nil)

		dPart:SetAttribute("AttackerUserId", nil)
		dPart:SetAttribute("AttributionDamage", nil)
		dPart:SetAttribute("AttributionExpire", nil)

		dPart.Parent = camFolder

		pcall(function()
			dPart:SetNetworkOwner(nil)
		end)

		local dx = pos.X - impactCenter.X
		local dy = pos.Y - impactCenter.Y
		local dz = pos.Z - impactCenter.Z
		local distSq = dx * dx + dy * dy + dz * dz

		local dirX, dirY, dirZ
		if distSq < 0.01 then
			local ang = mathrand() * math.pi * 2
			dirX = math.cos(ang)
			dirY = 0
			dirZ = math.sin(ang)
		else
			local inv = 1 / math.sqrt(distSq)
			dirX = dx * inv
			dirY = dy * inv
			dirZ = dz * inv
		end

		local impulse = mathrand() * (maxImpulse - minImpulse) + minImpulse
		impulse = impulse * impulseMul

		dPart.AssemblyLinearVelocity = Vector3new(
			dirX * impulse,
			dirY * impulse + upImpulse,
			dirZ * impulse
		)

		dPart.AssemblyAngularVelocity = Vector3new(
			(mathrand() * 2 - 1) * maxAngular * angMul,
			(mathrand() * 2 - 1) * maxAngular * angMul,
			(mathrand() * 2 - 1) * maxAngular * angMul
		)

		PartIds.Register(dPart, objectId)
		ins(ActiveParts, dPart)
		ins(spawned, dPart)
		ins(debrisList, {
			Id = objectId,
			CFrame = cf,
			Size = size,
			Color = dPart.Color,
			Material = dPart.Material,
		})
	end

	return spawned
end

return DebrisSpawner
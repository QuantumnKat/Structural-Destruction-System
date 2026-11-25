--!strict
--!native

local Constants = require(script.Parent.Parent.Support.Constants)

local mathmax = math.max

local PhysicsHelpers = {}

function PhysicsHelpers.ApplyDebrisPhysics(part: BasePart, matRule: any?)
	local density    = (matRule and matRule.DebrisDensity)    or Constants.DEBRIS_DENSITY
	local friction   = (matRule and matRule.DebrisFriction)   or Constants.DEBRIS_FRICTION
	local elasticity = (matRule and matRule.DebrisElasticity) or Constants.DEBRIS_ELASTICITY

	part.CustomPhysicalProperties = PhysicalProperties.new(
		density,
		friction,
		elasticity,
		Constants.DEBRIS_FRICTION_W,
		Constants.DEBRIS_ELASTICITY_W
	)
end

function PhysicsHelpers.ApplyFallingPhysics(part: BasePart, matRule: any?)
	part.Massless = false
	PhysicsHelpers.ApplyDebrisPhysics(part, matRule)

	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.Anchored = false
	part.CollisionGroup = "Debris"

	pcall(function()
		part:SetNetworkOwner(nil)
	end)
end

return PhysicsHelpers

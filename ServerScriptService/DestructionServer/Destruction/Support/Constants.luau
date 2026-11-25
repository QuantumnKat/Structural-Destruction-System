--!strict
-- Server/Destruction/modules/Constants.luau

local Constants = {
	FALLING_ID_OFFSET = 1_000_000,
	DEBRIS_ID_OFFSET  = 2_000_000,

	DEBRIS_DENSITY      = 5.0,
	DEBRIS_FRICTION     = 0.95,
	DEBRIS_ELASTICITY   = 0.02,
	DEBRIS_FRICTION_W   = 2.0,
	DEBRIS_ELASTICITY_W = 1.0,

	MIN_IMPULSE = 7,
	MAX_IMPULSE = 14,
	UP_IMPULSE  = 1.5,
	MAX_ANGULAR = 3.0,
}

return Constants

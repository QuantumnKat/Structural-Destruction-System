--!strict

local MapLoaderConfig = {
	INDEX_START       = 1,
	INDEX_MAX         = 4_000_000_000,
	INDEX_BATCH_YIELD = 200,         

	LOAD_BATCH_SIZE   = 200,          

	AABB_GAP_MAX      = 2.5,    
	NEIGHBOR_SEARCH   = 2.5,       

	DEFAULT = {
		Mass = 0, HP = 100, Hardness = 1,
		ForceTransmission = 1.0, StressResistance = 1.0,
		TensileStrength = 150, BendingForce = 300, CompressionStrength = 800,
		Pressure = 1.0, BreakRadius = 4.0,
		ShatterAirPercent = 0.5, MaxDebrisPerPart = 64,
		UnweldPercentage = 0.6,
		OnDisconnect = "Auto",
	},

	UNBREAKABLE_FOLDERS = {
		["Unbreakable"] = true, ["Indestructible"] = true,
		["Static"] = true,      ["Protected"] = true,
	},
	BREAKABLE_FOLDERS = {
		["Breakable"] = true, ["Destructible"] = true, ["Dynamic"] = true,
	},

	SERIALIZER_VERSION       = 4,
	SERIALIZER_VERSION_MIN   = 3,
}

return MapLoaderConfig

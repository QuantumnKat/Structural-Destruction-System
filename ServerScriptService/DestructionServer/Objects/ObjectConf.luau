--!strict

export type MaterialRule = {
	Destroyable: boolean?,
	MinImpactForce: number?,
	ImpulseMultiplier: number?,
	AngularMultiplier: number?,
	DebrisChunkSize: number?,
	DebrisDensity: number?,
	DebrisElasticity: number?,
	DebrisFriction: number?,
	HpMultiplier: number?,

	TensileStrength: number?,
	BendingForce: number?,
	CompressionStrength: number?,

	OnDisconnect: string?,
	BreakRadius: number?,
	ShatterAirPercent: number?,
	ShatterChunkSize: number?,
	ShatterMassThreshold: number?,
	MaxDebrisPerPart: number?,
}

export type CollideCheckConfig = {
	Enabled: boolean?, MinImpactForce: number?, CheckInterval: number?, EventName: string?,
}

export type ObjectConfig = {
	MaxInstances: number?, EnablePooling: boolean?, PrewarmCount: number?,
	AutoCleanup: boolean?, CleanupInterval: number?, MaxCulledLifetime: number?,
	CleanupYThreshold: number?, CleanupVelocityThreshold: number?,
	CollideCheck: CollideCheckConfig?,
	EventRegistry: { [string]: string }?,
	DefaultMaterialRule: MaterialRule?,
	MaterialRules: { [Enum.Material]: MaterialRule }?,
}

local DEFAULT_RULE: MaterialRule = {
	Destroyable = true, MinImpactForce = 0,
	ImpulseMultiplier = 1.0, AngularMultiplier = 1.0,
	DebrisChunkSize = 4, DebrisDensity = 5.0,
	OnDisconnect = "Detach", BreakRadius = 4,
	ShatterAirPercent = 0.5, ShatterChunkSize = 2,
	ShatterMassThreshold = 200, MaxDebrisPerPart = 64,
	TensileStrength = 150, BendingForce = 300, CompressionStrength = 800,
}

local ObjectConf: ObjectConfig = {
	MaxInstances = 5000, EnablePooling = true, PrewarmCount = 50,
	AutoCleanup = true, CleanupInterval = 5.0, MaxCulledLifetime = 30.0,
	CleanupYThreshold = -150, CleanupVelocityThreshold = 0.5,
	CollideCheck = {
		Enabled = true, MinImpactForce = 100,
		CheckInterval = 0.1, EventName = "CollideEvent",
	},
	EventRegistry = {
		CollapseEvent = "OnCollapse", CollideEvent = "OnCollide",
	},
	DefaultMaterialRule = DEFAULT_RULE,
	MaterialRules = {
		[Enum.Material.Wood]          = { OnDisconnect="Break", BreakRadius=5, ShatterMassThreshold=100, ImpulseMultiplier=1.3, DebrisDensity=2.0, DebrisChunkSize=3, TensileStrength=100, BendingForce=200, CompressionStrength=400 },
		[Enum.Material.Plastic]       = { OnDisconnect="Detach", ShatterMassThreshold=150, ImpulseMultiplier=1.2, DebrisDensity=3.0, TensileStrength=80, BendingForce=150, CompressionStrength=300 },
		[Enum.Material.Brick]         = { OnDisconnect="Break", BreakRadius=3, ShatterMassThreshold=300, DebrisDensity=6.0, TensileStrength=120, BendingForce=400, CompressionStrength=1200 },
		[Enum.Material.Concrete]      = { OnDisconnect="Detach", ShatterMassThreshold=500, DebrisDensity=7.0, TensileStrength=200, BendingForce=600, CompressionStrength=2000 },
		[Enum.Material.Metal]         = { OnDisconnect="Detach", ShatterMassThreshold=800, ImpulseMultiplier=0.6, AngularMultiplier=0.7, DebrisDensity=8.0, TensileStrength=800, BendingForce=1500, CompressionStrength=3000 },
		[Enum.Material.DiamondPlate]  = { Destroyable=false },
		[Enum.Material.Glass]         = { OnDisconnect="Shatter", ShatterAirPercent=0.85, ShatterChunkSize=1, ShatterMassThreshold=20, ImpulseMultiplier=1.5, DebrisChunkSize=2, TensileStrength=10, BendingForce=20, CompressionStrength=50 },
		[Enum.Material.Rock]          = { OnDisconnect="Detach", ShatterMassThreshold=600, DebrisDensity=8.0, TensileStrength=250, BendingForce=800, CompressionStrength=2500 },
		[Enum.Material.CorrodedMetal] = { OnDisconnect="Break", BreakRadius=4, ShatterMassThreshold=400, TensileStrength=300, BendingForce=600, CompressionStrength=1000 },
	},
}

local MERGED_CACHE: { [Enum.Material]: MaterialRule } = nil :: any
local DEFAULT_CACHED: MaterialRule = nil :: any

local function buildMergedCache()
	local defaultCopy: any = table.clone(DEFAULT_RULE)
	DEFAULT_CACHED = table.freeze(defaultCopy)

	local cache: { [Enum.Material]: MaterialRule } = {}
	local materialRules = ObjectConf.MaterialRules
	if materialRules then
		for mat, rule in pairs(materialRules) do
			local merged: any = {}
			for k, v in pairs(DEFAULT_RULE) do
				merged[k] = v
			end
			for k, v in pairs(rule) do
				merged[k] = v
			end
			cache[mat] = table.freeze(merged)
		end
	end
	MERGED_CACHE = cache
end

buildMergedCache()

local module = {}

function module.GetConfig(): ObjectConfig
	return ObjectConf
end

function module.GetMaterialRule(material: Enum.Material): MaterialRule
	local r = MERGED_CACHE[material]
	if r then
		return r
	end
	return DEFAULT_CACHED
end

return module

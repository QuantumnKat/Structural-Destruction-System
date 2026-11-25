--!strict

export type LODTier = {
	MaxDistance: number?,     
	Mode: string?,              
	UpdateFrequency: number?,   
	ClientLerpSpeed: number?,
	ExtrapolationTime: number?,
}

export type LOD = {
	Enabled: boolean?,
	DebugDraw: boolean?,
	MinimumBaseDistance: number?,
	RadiusFocalParticle: number?,
	BaseDistanceRadiusMultiplier: number?,
	BaseDistancesForFullPrediction: number?,
	BaseDistancesForResimulationMode: number?,
	TimeOverDistance: number?,
	MaxTimeDelay: number?,
	Tiers: { LODTier }?,
}

export type AOI = {
	NetCullDistanceSquared: number?,  
	NetUpdateFrequency: number?,      
	AlwaysRelevant: boolean?,
	StreamingMinRadius: number?,      
	StreamingTargetRadius: number?, 
	UseCameraAsFocalPoint: boolean?,
	RelevancyCheckInterval: number?,
}

export type Quantization = {
	PositionStep: number?,            
	RotationStep: number?,           
	VelocityStep: number?,           
}

export type Priority = {
	PlayerWeight: number?,
	VehicleWeight: number?,
	PropWeight: number?,
	NPCWeight: number?,
}

export type Dormancy = {
	Enabled: boolean?,
	IdleThreshold: number?,            
	WakeOnDistance: number?,          
}

type ConfigData = {
	LOD: LOD,
	AOI: AOI,
	Quantization: Quantization,
	Priority: Priority,
	Dormancy: Dormancy,
}

type ConfigAPI = {
	GetConfig: (Category: string) -> any,
	GetConfigFlag: (Category: string, Flag: string) -> any,
}

local Config: ConfigData & ConfigAPI = {
	LOD = {
		Enabled = true,
		DebugDraw = true,
		MinimumBaseDistance = 100,
		RadiusFocalParticle = 40,
		BaseDistanceRadiusMultiplier = 0.75,
		BaseDistancesForFullPrediction = 2.5,
		BaseDistancesForResimulationMode = 1.0,
		TimeOverDistance = 0.15,
		MaxTimeDelay = 250,
		Tiers = {
			{ MaxDistance = 130,  Mode = "Resimulation",    UpdateFrequency = 20, ClientLerpSpeed = 40, ExtrapolationTime = 0.1 },
			{ MaxDistance = 325,  Mode = "FullPrediction",  UpdateFrequency = 10, ClientLerpSpeed = 25, ExtrapolationTime = 0.15 },
			{ MaxDistance = 1200, Mode = "Predictive",      UpdateFrequency = 5,  ClientLerpSpeed = 15, ExtrapolationTime = 0.25 },
			{ MaxDistance = nil,  Mode = "Culled",          UpdateFrequency = 0,  ClientLerpSpeed = 15, ExtrapolationTime = 0.0 },
		},
	},

	AOI = {
		NetCullDistanceSquared = 1_500_000,
		NetUpdateFrequency = 30,
		AlwaysRelevant = false,
		StreamingMinRadius = 640,
		StreamingTargetRadius = 10240,
		UseCameraAsFocalPoint = true,
		RelevancyCheckInterval = 0.1,
	},

	Quantization = {
		PositionStep = 0.05,
		RotationStep = 10,
		VelocityStep = 1,
	},

	Priority = {
		PlayerWeight = 10,
		VehicleWeight = 7,
		NPCWeight = 4,
		PropWeight = 1,
	},

	Dormancy = {
		Enabled = true,
		IdleThreshold = 2.0,
		WakeOnDistance = 1500,
	},
}

function Config.GetConfig(Category: string): any
	local cfg = (Config :: any)[Category]
	assert(
		cfg ~= nil,
		string.format("[Config] category '%s' does not exist", Category)
	)
	return cfg
end

function Config.GetConfigFlag(Category: string, Flag: string): any
	local cat = (Config :: any)[Category]
	assert(
		cat ~= nil,
		string.format("[Config] category '%s' does not exist", Category)
	)

	local flag = cat[Flag]
	assert(
		flag ~= nil,
		string.format("[Config] flag '%s' from category '%s' does not exist", Category, Flag)
	)
	return flag
end

return Config

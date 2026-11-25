--!strict
-- ReplicatedStorage.Shared.Net/NetworkConf.luau

export type PartialExtrapolation = {
	Enabled: boolean?,
	MaxExtrapTime: number?,
	MinVelocity: number?,
	MaxVelocity: number?,
	VelocitySmoothing: number?,
	MaxDrift: number?,
	PredictionOffset: number?,
	LockY: boolean?,
	ScaleBySpeed: boolean?,
}

export type ExtrapolationConfig = PartialExtrapolation & {
	PerTierOverrides: { [string]: PartialExtrapolation }?,
}

export type ChunkingConfig = {
	MaxPacketsPerChunk: number?,
	MaxBytesPerChunk: number?,
	MaxChunksPerSend: number?,
	MaxPartsPerFrame: number?,
}

export type NetworkData = {
	Chunking: ChunkingConfig,
	Extrapolation: ExtrapolationConfig,
	Debug: { Verbose: boolean? }?,
}

local NetworkConf: NetworkData = {
	Chunking = {
		MaxPacketsPerChunk = 64,
		MaxBytesPerChunk   = 800,
		MaxChunksPerSend   = 4,
		MaxPartsPerFrame   = 512,
	},

	Extrapolation = {
		Enabled           = true,
		MaxExtrapTime     = 0.15,
		MinVelocity       = 0.5,
		MaxVelocity       = 500,
		VelocitySmoothing = 0.20,
		MaxDrift          = 10,
		PredictionOffset  = 0.05,
		LockY             = true,
		ScaleBySpeed      = true,

		PerTierOverrides = {
			Resimulation = {
				Enabled           = false,
				MaxExtrapTime     = 0.05,
				VelocitySmoothing = 0.15,
				MaxDrift          = 5,
			},
			FullPrediction = {
				Enabled           = true,
				MaxExtrapTime     = 0.12,
				VelocitySmoothing = 0.25,
				MaxDrift          = 8,
			},
			Predictive = {
				Enabled           = true,
				MaxExtrapTime     = 0.25,
				VelocitySmoothing = 0.40,
				MaxDrift          = 15,
			},
			Culled = {
				Enabled       = true,
				MaxExtrapTime = 0,
			},
		},
	},

	Debug = { Verbose = false },
}

function NetworkConf.Get(category: string): any
	local cfg = (NetworkConf :: any)[category]
	assert(cfg ~= nil, string.format("[NetworkConf] category '%s' does not exist", category))
	return cfg
end

function NetworkConf.GetTierExtrapolation(tier: { Mode: string?, ExtrapolationTime: number? }): { [string]: any }
	local base     = NetworkConf.Extrapolation
	local tierName = tier.Mode or "Predictive"
	local override = base.PerTierOverrides and base.PerTierOverrides[tierName]

	local merged: { [string]: any } = {}
	for k, v in pairs(base) do
		if k ~= "PerTierOverrides" then
			merged[k] = v
		end
	end
	if override then
		for k, v in pairs(override) do
			if v ~= nil then merged[k] = v end
		end
	end
	if tier.ExtrapolationTime ~= nil then
		merged.MaxExtrapTime = tier.ExtrapolationTime
	end
	return merged
end

function NetworkConf.Setup(custom: { [string]: any }?)
	if not custom then return end
	for section, values in pairs(custom) do
		local target = (NetworkConf :: any)[section]
		if type(values) == "table" and target then
			for k, v in pairs(values) do
				if v ~= nil then target[k] = v end
			end
		end
	end
end

return NetworkConf

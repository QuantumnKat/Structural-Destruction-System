--!strict
--!native

local Config = require(script.Parent.InterestConf)
local LODConf = Config.GetConfig("LOD") :: any

type TierInfo = {
	Mode: string,
	UpdateFrequency: number,
}

local LOD = {}

local BaseDistance: number = (LODConf.MinimumBaseDistance or 100)
	+ (LODConf.RadiusFocalParticle or 40) * (LODConf.BaseDistanceRadiusMultiplier or 0.75)

local ResimRadius: number = BaseDistance * (LODConf.BaseDistancesForResimulationMode or 1.0)
local FullPredRadius: number = BaseDistance * (LODConf.BaseDistancesForFullPrediction or 2.5)
local MaxTimeDelay: number = LODConf.MaxTimeDelay or 250
local TimeOverDistance: number = LODConf.TimeOverDistance or 0.15

local TierTables: {TierInfo} = {}
local TierMaxSq: {number} = {}
local TierPeriod: {number} = {}
local TierCount = 0

local function register(mode: string, frequency: number, maxDistance: number?)
	TierCount += 1
	TierTables[TierCount] = { Mode = mode, UpdateFrequency = frequency }
	TierMaxSq[TierCount] = if maxDistance then maxDistance * maxDistance else math.huge
	TierPeriod[TierCount] = if frequency > 0 then 1 / frequency else math.huge
end

local source = LODConf.Tiers
if source and #source > 0 then
	local sorted = table.clone(source)
	table.sort(sorted, function(a: any, b: any): boolean
		if a.MaxDistance == nil then
			return false
		end
		if b.MaxDistance == nil then
			return true
		end
		return a.MaxDistance < b.MaxDistance
	end)
	for _, tier in sorted do
		register(tier.Mode or "Culled", tier.UpdateFrequency or 0, tier.MaxDistance)
	end
else
	register("Resimulation", 60, ResimRadius)
	register("FullPrediction", 30, FullPredRadius)
	register("Predictive", 15, nil)
end

function LOD.GetTierIndex(distSq: number): number
	for i = 1, TierCount do
		if distSq < TierMaxSq[i] then
			return i
		end
	end
	return TierCount
end

function LOD.GetPeriod(distSq: number): number
	return TierPeriod[LOD.GetTierIndex(distSq)]
end

function LOD.GetTimeDelay(distance: number): number
	return math.clamp((distance - FullPredRadius) * TimeOverDistance, 0, MaxTimeDelay)
end

function LOD.GetTier(distance: number): TierInfo
	return TierTables[LOD.GetTierIndex(distance * distance)]
end

function LOD.GetType(distance: number): string
	return LOD.GetTier(distance).Mode
end

function LOD.GetUpdateFrequency(distance: number): number
	return LOD.GetTier(distance).UpdateFrequency
end

function LOD.CalcDebug(distance: number)
	local tier = LOD.GetTier(distance)
	return {
		Mode = tier.Mode,
		UpdateFrequency = tier.UpdateFrequency,
		TimeDelay = LOD.GetTimeDelay(distance),
		BaseDistance = BaseDistance,
		ResimRadius = ResimRadius,
		FullPredRadius = FullPredRadius,
	}
end

LOD.BaseDistance = BaseDistance
LOD.ResimRadius = ResimRadius
LOD.FullPredRadius = FullPredRadius

return LOD

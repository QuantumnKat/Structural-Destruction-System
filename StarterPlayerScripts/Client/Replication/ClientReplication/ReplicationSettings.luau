--!strict
-- EditorSync: refactor-v1
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InterestConf = require(ReplicatedStorage.Shared.Net.Interest.InterestConf)
local NetworkConf: any = require(ReplicatedStorage.Shared.Net.NetworkConf)
local LODConf = InterestConf.GetConfig("LOD")
local mathmax, mathclamp = math.max, math.clamp
local DEFAULTS: { [string]: any } = {
	Mode          = "Hermite",   -- "Hermite" | "Linear"
	BufferSize    = 6,
	Tension       = 1.0,         -- 0 = linear, 1 = Catmull-Rom
	TangentClamp  = 1.5,
	GapReset      = 1.0,
	LocalAnchor   = true,
	BulkMoveMode  = "FireCFrameChanged",
	LodRecheck    = 0.25,
	TargetTTL     = 3.0,
	SweepInterval = 1.0,
	UnregisteredTTL = 30.0,
	ResolveCooldown = 1.0,
	ScanOnStart     = true,

	Delay = {
		Mode           = "Adaptive", -- "Adaptive" | "Fixed"
		Fixed          = 0.10,
		Initial        = 0.10,
		Min            = 0.04,
		Max            = 0.35,
		IntervalFactor = 2.0,
		JitterFactor   = 2.0,
		IntervalEMA    = 0.15,
		SlewUp         = 0.25,
		SlewDown       = 0.05,
	},

	Clock = {
		DownRate        = 0.02,
		UpRate          = 0.002,
		JitterEMA       = 0.05,
		MaxJitterSample = 0.25,
	},

	Extrapolation = {
		Enabled           = true,
		MinVelocity       = 0.5,
		MaxVelocity       = 1e9,
		MaxExtrapTime     = 0.15,
		MaxDrift          = 1e9,
		LockY             = false,
		Damping           = 6.0,
		VelocitySmoothing = 0.5,
	},

	ErrorCorrection = {
		Enabled      = true,
		DecayRate    = 14,
		SnapDistance = 25,
	},
}

local function deepCopy(t: any): any
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = deepCopy(v) end
	return out
end

local function merge(dst: any, src: any)
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" then
			merge(dst[k], v)
		else
			dst[k] = deepCopy(v)
		end
	end
end

local function buildConf(tier: any): any
	local conf = deepCopy(DEFAULTS)
	local interp = NetworkConf.Interp
	if type(interp) == "table" then
		merge(conf, interp)
		if type(interp.ExtrapolationMaxMs) == "number" then
			conf.Extrapolation.MaxExtrapTime = interp.ExtrapolationMaxMs / 1000
		end
	end
	if type(tier) == "table" then
		if type(tier.Extrapolation) == "table" then
			merge(conf.Extrapolation, tier.Extrapolation)
		end
		if type(tier.Interp) == "table" then
			merge(conf, tier.Interp)
		end
	end
	conf.UseHermite = conf.Mode == "Hermite"
	conf.BufferSize = mathmax(3, math.floor(conf.BufferSize))
	conf.Delay.SlewUp = mathclamp(conf.Delay.SlewUp, 0, 0.9)
	return conf
end

local Tiers: { any } = table.clone(LODConf.Tiers)
table.sort(Tiers, function(a, b)
	if a.MaxDistance == nil then return false end
	if b.MaxDistance == nil then return true end
	return a.MaxDistance < b.MaxDistance
end)
if #Tiers == 0 then Tiers = { {} } end

local BASE: any = buildConf(nil)
local TierConf: { any } = {}
for i = 1, #Tiers do
	TierConf[i] = buildConf(Tiers[i])
end

local LOCAL_ANCHOR: boolean   = BASE.LocalAnchor == true
local SKIP_UNCHANGED: boolean = LOCAL_ANCHOR
local TARGET_TTL: number      = BASE.TargetTTL
local SWEEP_INTERVAL: number  = BASE.SweepInterval
local LOD_RECHECK: number     = BASE.LodRecheck
local UNREG_TTL: number          = BASE.UnregisteredTTL
local RESOLVE_COOLDOWN: number   = BASE.ResolveCooldown
local DYN_TAG: string            = BASE.DynTag or "DynPart"
local BULK_INITIAL_SIZE       = 256

local BULK_MODE: any = Enum.BulkMoveMode.FireCFrameChanged
do
	local ok, item = pcall(function()
		return (Enum.BulkMoveMode :: any)[BASE.BulkMoveMode]
	end)
	if ok and item then BULK_MODE = item end
end


return { BASE = BASE, TierConf = TierConf, Tiers = Tiers, LOCAL_ANCHOR = LOCAL_ANCHOR, SKIP_UNCHANGED = SKIP_UNCHANGED, TARGET_TTL = TARGET_TTL, SWEEP_INTERVAL = SWEEP_INTERVAL, LOD_RECHECK = LOD_RECHECK, UNREG_TTL = UNREG_TTL, RESOLVE_COOLDOWN = RESOLVE_COOLDOWN, DYN_TAG = DYN_TAG, BULK_INITIAL_SIZE = BULK_INITIAL_SIZE, BULK_MODE = BULK_MODE }

--!strict
local Settings = require(script.Parent.ReplicationSettings)
local BASE, TierConf = Settings.BASE, Settings.TierConf
local ZERO = Vector3.zero
local mathclamp = math.clamp
local function seedOffset(data: any, fromPos: Vector3, toPos: Vector3)
	local ec = data.Conf.ErrorCorrection
	if not ec.Enabled then
		data.Offset = ZERO
		data.HasOffset = false
		return
	end
	local diff = fromPos - toPos
	local m2 = diff:Dot(diff)
	if m2 > ec.SnapDistance * ec.SnapDistance or m2 < 1e-6 then
		data.Offset = ZERO
		data.HasOffset = false
	else
		data.Offset = diff
		data.HasOffset = true
	end
end

local function initialDelay(conf: any): number
	local dc = conf.Delay
	local d = if dc.Mode == "Fixed" then dc.Fixed else dc.Initial
	return mathclamp(d, dc.Min, dc.Max)
end

local function newTarget(cf: CFrame, serverT: number, now: number, part: BasePart?): any
	local conf = TierConf[1]
	local cap: number = BASE.BufferSize
	local delay = initialDelay(conf)

	local data: any = {
		T = table.create(cap, 0),
		C = table.create(cap, cf),
		Cap = cap, Head = 1, Count = 1,
		Vel = ZERO, Interval = 0,
		Delay = delay, DelayTarget = delay,
		LastServerT = serverT, LastArrival = now,
		Offset = ZERO, HasOffset = false,
		Cur = cf, Tier = 1, NextTier = 0, Conf = conf,
		Sleeping = false, Idle = false,
	}
	data.T[1] = serverT

	if part and part.Parent then
		local cur = part.CFrame
		data.Cur = cur
		seedOffset(data, cur.Position, cf.Position)
	end
	return data
end


return table.freeze({ New = newTarget, InitialDelay = initialDelay, SeedOffset = seedOffset })

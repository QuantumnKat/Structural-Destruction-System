--!strict
-- EditorSync: refactor-v1
--!native
return function(ClientReplication: any, deps: any)
local SWEEP_INTERVAL = deps.SWEEP_INTERVAL
local UNREG_TTL = deps.UNREG_TTL
local TARGET_TTL = deps.TARGET_TTL
local TierConf = deps.TierConf
local LOD_RECHECK = deps.LOD_RECHECK
local SKIP_UNCHANGED = deps.SKIP_UNCHANGED
local BULK_MODE = deps.BULK_MODE
local getFocalPosition = deps.getFocalPosition
local getTierIndex = deps.getTierIndex
local sampleBuffer = deps.sampleBuffer
local ZERO = deps.ZERO
local osclock = deps.osclock
local mathexp = deps.mathexp
local mathsqrt = deps.mathsqrt
function ClientReplication:UpdateLerp(dt: number)
	local clockOffset: number? = self._clockOffset
	if clockOffset == nil then return end

	local targets = self.Targets
	local parts = self.DynamicParts
	local now = osclock()
	local renderBase = now - clockOffset
	local focal = getFocalPosition(self.LocalPlayer)

	local bulkParts   = self._bulkParts
	local bulkCFrames = self._bulkCFrames
	local prevCount   = self._bulkCount

	self._sweepTimer += dt
	local doSweep = false
	if self._sweepTimer >= SWEEP_INTERVAL then
		self._sweepTimer = 0
		doSweep = true
	end

	if doSweep then
		local ra = self._resolveAt
		for k, t in pairs(ra) do
			if now > t + 5 then ra[k] = nil end
		end
	end

	local decays = self._decay
	for i = 1, #TierConf do
		decays[i] = mathexp(-TierConf[i].ErrorCorrection.DecayRate * dt)
	end

	local n = 0
	for partId, data in pairs(targets) do
		local part = parts[partId]

		if part == nil or part.Parent == nil then
			part = self:_tryResolve(partId, now)
			if part == nil then
				if doSweep and now - data.LastArrival > UNREG_TTL then
					targets[partId] = nil
				end
				continue
			end
		end

		if data.Idle then
			if doSweep and now - data.LastArrival > TARGET_TTL then
				targets[partId] = nil
			end
			continue
		end

		local conf = data.Conf

		if focal and now >= data.NextTier then
			local d = data.Cur.Position - focal
			local ti = getTierIndex(mathsqrt(d:Dot(d)))
			if ti ~= data.Tier then
				data.Tier = ti
				conf = TierConf[ti]
				data.Conf = conf
			end
			data.NextTier = now + LOD_RECHECK * (1 + (partId % 4) * 0.25)
		end

		local dd: number = data.DelayTarget - data.Delay
		if dd ~= 0 then
			local dc = conf.Delay
			local up = dc.SlewUp * dt
			local down = dc.SlewDown * dt
			if dd > up then dd = up elseif dd < -down then dd = -down end
			data.Delay += dd
		end

		local renderT = renderBase - data.Delay
		local target = sampleBuffer(data, renderT, conf)

		if data.HasOffset then
			local off: Vector3 = data.Offset * decays[data.Tier]
			if off:Dot(off) < 1e-6 then
				data.Offset = ZERO
				data.HasOffset = false
			else
				data.Offset = off
				target += off
			end
		end

		local newestT: number = data.T[data.Head]

		if data.Sleeping and renderT >= newestT and not data.HasOffset then
			n += 1
			bulkParts[n] = part
			bulkCFrames[n] = target
			targets[partId] = nil
			continue
		end

		if (not SKIP_UNCHANGED) or target ~= data.Cur then
			n += 1
			bulkParts[n] = part
			bulkCFrames[n] = target
			data.Cur = target
		end

		if not data.HasOffset and renderT >= newestT + conf.Extrapolation.MaxExtrapTime then
			data.Idle = true
		end
	end

	if n > 0 then
		for i = n + 1, prevCount do
			bulkParts[i] = nil
			bulkCFrames[i] = nil
		end
		self._bulkCount = n
		workspace:BulkMoveTo(bulkParts, bulkCFrames, BULK_MODE)
	elseif prevCount > 0 then
		for i = 1, prevCount do
			bulkParts[i] = nil
			bulkCFrames[i] = nil
		end
		self._bulkCount = 0
	end
end


end

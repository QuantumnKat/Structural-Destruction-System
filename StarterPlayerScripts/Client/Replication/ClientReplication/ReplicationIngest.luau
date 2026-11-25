--!strict
-- EditorSync: refactor-v1
--!native
return function(ClientReplication: any, deps: any)
local BASE = deps.BASE
local LOCAL_ANCHOR = deps.LOCAL_ANCHOR
local SETTLE_EPS_SQ = deps.SETTLE_EPS_SQ
local newTarget = deps.newTarget
local initialDelay = deps.initialDelay
local seedOffset = deps.seedOffset
local pushSnap = deps.pushSnap
local sampleBuffer = deps.sampleBuffer
local ZERO = deps.ZERO
local mathclamp = deps.mathclamp
local mathabs = deps.mathabs
local readu32 = deps.readu32
local readf64 = deps.readf64
local readi16 = deps.readi16
local PACKET_BYTES = deps.PACKET_BYTES
local TRAILER_BYTES = deps.TRAILER_BYTES
local SLEEP_FLAG = deps.SLEEP_FLAG
local Quantize = deps.Quantize
local osclock = deps.osclock
function ClientReplication:_syncClock(serverT: number, now: number)
	local c = BASE.Clock
	local sample = now - serverT
	local off: number? = self._clockOffset

	if off == nil then
		self._clockOffset = sample
	else
		local rate = if sample < off then c.DownRate else c.UpRate
		self._clockOffset = off + (sample - off) * rate

		local lastArr: number? = self._lastArrival
		if lastArr then
			local j = mathabs((now - lastArr) - (serverT - self._lastServerT))
			if j > c.MaxJitterSample then j = c.MaxJitterSample end
			self._jitter += (j - self._jitter) * c.JitterEMA
		end
	end
	self._lastArrival = now
	self._lastServerT = serverT
end

function ClientReplication:_ingest(
	partId: number, cf: CFrame, serverT: number, now: number,
	sleeping: boolean, clockOffset: number
)
	local part = self.DynamicParts[partId]
	if part and part.Parent == nil then part = nil end
	if part == nil then
		part = self:_tryResolve(partId, now)
	end

	if LOCAL_ANCHOR and part and not part.Anchored then
		part.Anchored = true
	end

	local data: any = self.Targets[partId]
	if data == nil then
		if sleeping and part then
			local d = part.Position - cf.Position
			if d:Dot(d) < SETTLE_EPS_SQ then return end
		end
		data = newTarget(cf, serverT, now, part)
		data.Sleeping = sleeping
		self.Targets[partId] = data
		return
	end

	if serverT <= data.LastServerT then return end

	local conf = data.Conf
	local gap = serverT - data.LastServerT
	data.LastServerT = serverT
	data.LastArrival = now
	data.Idle = false

	if gap > conf.GapReset then
		local curPos = data.Cur.Position
		data.Count = 0
		data.Head = 0
		data.Interval = 0
		data.Vel = ZERO
		local d0 = initialDelay(conf)
		data.Delay = d0
		data.DelayTarget = d0
		pushSnap(data, cf, serverT)
		data.Sleeping = sleeping
		seedOffset(data, curPos, cf.Position)
		return
	end

	local ec = conf.ErrorCorrection
	local renderT = now - clockOffset - data.Delay
	local before: CFrame? = nil
	if ec.Enabled then
		before = sampleBuffer(data, renderT, conf)
	end

	local prevCF: CFrame = data.C[data.Head]
	local vInst = (cf.Position - prevCF.Position) / gap
	if sleeping then
		data.Vel = ZERO
	elseif data.Sleeping or data.Count <= 1 then
		data.Vel = vInst
	else
		data.Vel = (data.Vel :: Vector3):Lerp(vInst, conf.Extrapolation.VelocitySmoothing)
	end

	local dc = conf.Delay
	local iv: number = data.Interval
	if iv > 0 then
		iv += (gap - iv) * dc.IntervalEMA
	else
		iv = gap
	end
	data.Interval = iv
	if dc.Mode == "Fixed" then
		data.DelayTarget = dc.Fixed
	else
		data.DelayTarget = mathclamp(
			iv * dc.IntervalFactor + self._jitter * dc.JitterFactor,
			dc.Min, dc.Max
		)
	end

	pushSnap(data, cf, serverT)
	data.Sleeping = sleeping

	if before then
		local after = sampleBuffer(data, renderT, conf)
		local off: Vector3 = data.Offset + (before.Position - after.Position)
		local m2 = off:Dot(off)
		if m2 > ec.SnapDistance * ec.SnapDistance or m2 < 1e-6 then
			data.Offset = ZERO
			data.HasOffset = false
		else
			data.Offset = off
			data.HasOffset = true
		end
	end
end

function ClientReplication:ProcessBuffer(buf: buffer)
	local len = buffer.len(buf)
	if len < TRAILER_BYTES then return end

	local count = readu32(buf, len - 4)
	if count == 0 then return end
	if len ~= count * PACKET_BYTES + TRAILER_BYTES then
		warn("ClientReplication: bad buffer length")
		return
	end

	local serverT = readf64(buf, len - 12)
	local now = osclock()
	self:_syncClock(serverT, now)
	local clockOffset: number = self._clockOffset :: number

	local offset = 0
	for _ = 1, count do
		local rawId = readu32(buf, offset)
		local qx  = readi16(buf, offset + 4)
		local qy  = readi16(buf, offset + 6)
		local qz  = readi16(buf, offset + 8)
		local qrx = readi16(buf, offset + 10)
		local qry = readi16(buf, offset + 12)
		local qrz = readi16(buf, offset + 14)
		offset += PACKET_BYTES

		local sleeping = rawId >= SLEEP_FLAG
		local partId = if sleeping then rawId - SLEEP_FLAG else rawId

		local cf = Quantize.Int16ToCFrame(qx, qy, qz, qrx, qry, qrz)
		self:_ingest(partId, cf, serverT, now, sleeping, clockOffset)
	end
end


end

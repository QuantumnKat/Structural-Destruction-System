--!strict
-- EditorSync: refactor-v1
--!native
local mathexp = math.exp
local function pushSnap(data: any, cf: CFrame, t: number)
	local h = data.Head % data.Cap + 1
	data.Head = h
	data.T[h] = t
	data.C[h] = cf
	if data.Count < data.Cap then
		data.Count += 1
	end
end

local function extrapolate(data: any, extra: number, ex: any): CFrame
	local newest: CFrame = data.C[data.Head]
	if data.Sleeping or not ex.Enabled then
		return newest
	end

	local vel: Vector3 = data.Vel
	local speed = vel.Magnitude
	if speed < ex.MinVelocity or speed > ex.MaxVelocity then
		return newest
	end

	if extra > ex.MaxExtrapTime then extra = ex.MaxExtrapTime end
	local damping: number = ex.Damping
	if damping > 0 then
		extra = (1 - mathexp(-damping * extra)) / damping
	end

	local disp = vel * extra
	local drift = disp.Magnitude
	if drift > ex.MaxDrift then
		disp = disp * (ex.MaxDrift / drift)
	end

	local base = newest.Position
	local pos = base + disp
	if ex.LockY then
		pos = Vector3.new(pos.X, base.Y, pos.Z)
	end
	return newest.Rotation + pos
end

local function sampleBuffer(data: any, renderT: number, conf: any): CFrame
	local T, C, cap = data.T, data.C, data.Cap
	local head, count = data.Head, data.Count

	local newestT: number = T[head]
	if renderT >= newestT then
		return extrapolate(data, renderT - newestT, conf.Extrapolation)
	end

	local idxB = head
	local k = 0
	while k < count - 1 do
		local idxA = (idxB - 2) % cap + 1
		local tA: number = T[idxA]
		if tA <= renderT then
			local tB: number = T[idxB]
			local span = tB - tA
			if span <= 1e-6 then return C[idxB] end

			local u = (renderT - tA) / span
			local cfA: CFrame = C[idxA]
			local cfB: CFrame = C[idxB]

			if not conf.UseHermite then
				return cfA:Lerp(cfB, u)
			end

			local pA = cfA.Position
			local pB = cfB.Position
			local chord = (pB - pA) / span
			local limit = chord.Magnitude * conf.TangentClamp

			local vA = chord
			local vB = chord

			if k + 2 < count then
				local idxP = (idxA - 2) % cap + 1
				vA = (pB - C[idxP].Position) / (tB - T[idxP])
			end
			if k > 0 then
				local idxN = idxB % cap + 1
				vB = (C[idxN].Position - pA) / (T[idxN] - tA)
			end

			local m = vA.Magnitude
			if m > limit and m > 0 then vA = vA * (limit / m) end
			m = vB.Magnitude
			if m > limit and m > 0 then vB = vB * (limit / m) end

			local tension: number = conf.Tension
			if tension ~= 1 then
				vA = chord:Lerp(vA, tension)
				vB = chord:Lerp(vB, tension)
			end

			local u2 = u * u
			local u3 = u2 * u
			local h00 = 2 * u3 - 3 * u2 + 1
			local h10 = u3 - 2 * u2 + u
			local h01 = -2 * u3 + 3 * u2
			local h11 = u3 - u2
			local pos = pA * h00 + vA * (span * h10) + pB * h01 + vB * (span * h11)

			return cfA:Lerp(cfB, u).Rotation + pos
		end
		idxB = idxA
		k += 1
	end

	return C[idxB]
end


return { Push = pushSnap, Sample = sampleBuffer }

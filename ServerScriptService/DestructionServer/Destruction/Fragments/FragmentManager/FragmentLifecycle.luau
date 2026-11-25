--!strict
-- EditorSync: refactor-v1
--!native
return function(deps: any)
local S, Conf = deps.State, deps.Config
local SnapshotCodec = deps.SnapshotCodec
local mark, breakWeldsOf, releasePart = deps.Mark, deps.BreakWeldsOf, deps.ReleasePart
local osclock, mathmin, mathmax, mathclamp = os.clock, math.min, math.max, math.clamp
local FragmentManager = { CaptureSnapshot = deps.CaptureSnapshot }
function FragmentManager.Step(_dt: number)
	if not S.inited then return end
	local active: { BasePart } = S.active
	local V = Conf.Vanish
	local n = #active

	if n > 0 then
		local budget = mathmin(n, V.MaxPartsPerStep)
		local now = osclock()
		local cursor: number = S.cursor
		local state: buffer = S.state

		for _ = 1, budget do
			if n == 0 then break end
			cursor = cursor % n + 1
			local p = active[cursor]
			local drop = false
			local release = false

			if p == nil or p.Parent == nil then
				drop = true
			else
				local s = p.Size
				local vol = s.X * s.Y * s.Z
				local ext = mathmax(s.X, s.Y, s.Z)
				local sleeping = p:GetAttribute("IsSleeping") == true
				local spawn = p:GetAttribute("_SpawnTime")
				local age = 0
				if type(spawn) == "number" then
					age = now - spawn
				else
					p:SetAttribute("_SpawnTime", now)
				end

				local pid = p:GetAttribute("PartIndex")
				if type(pid) == "number" and pid <= S.maxIdx then
					local st = SnapshotCodec.GetState(S.state :: buffer, pid)
					if sleeping and st == 1 then
						mark(pid, 3)
					elseif not sleeping and st == 3 then
						mark(pid, 1)
					end
				end

				local kill = false
				if vol < V.TinyVolume or ext < V.TinyExtent then
					kill = age >= V.TinyLifetime or (sleeping and age >= V.TinySettledTTL)
				elseif V.LifetimeEnabled and sleeping then
					local life = mathclamp(V.BaseLifetime * (vol / V.RefVolume) ^ (1 / 3), V.MinLifetime, V.MaxLifetime)
					kill = age >= life
				end

				if kill then
					drop = true
					local id = p:GetAttribute("ObjectId")
					local pid2 = p:GetAttribute("PartIndex")
					breakWeldsOf(p)
					if type(pid2) == "number" then
						mark(pid2, 2)
						if S.event then S.event:FireAllClients("DESTROY_PART", pid2) end
						if S.log then S.log:Destroy(pid2) end
					elseif S.log and type(id) == "number" then
						S.log:Vanish(id)
					end
					release = true
				end
			end

			if drop then
				active[cursor] = active[n]
				active[n] = nil
				n -= 1
				cursor -= 1
				if release then releasePart(p) end
				n = #active
			end
		end
		S.cursor = cursor
	end

	local sc = Conf.Snapshot
	if sc.Enabled and sc.Interval > 0 then
		local now = osclock()
		if now - S.lastSnap >= sc.Interval then
			if S.dirty >= sc.MinChangedEvents then
				FragmentManager.CaptureSnapshot()
			else
				S.lastSnap = now
			end
		end
	end
end

return FragmentManager.Step
end

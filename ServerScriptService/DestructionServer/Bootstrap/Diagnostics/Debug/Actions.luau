--!strict
--!native

local Actions: any = {}

function Actions.Init(ctx: any, Debug: any)
	local State, Mods, Remote, Log = ctx.State, ctx.Mods, ctx.Remote, ctx.Log
	local Handler = Mods.Handler
	local R = Debug.Register

	R("hit", function(_, idx: any, force: any)
		if not State.graph then return "no graph" end
		if type(idx) ~= "number" or type(force) ~= "number" then return "invalid args" end
		Handler.HandleHit(State.graph, nil, idx, force, Remote.Event, State.ActiveParts)
		State.MarkDirty()
		return ("Hit %d force %d"):format(idx, force)
	end)

	R("hit_force", function(_, idx: any, force: any)
		if not State.graph then return "no graph" end
		if type(idx) ~= "number" then return "invalid idx: " .. tostring(idx) end
		if type(force) ~= "number" then return "invalid force: " .. tostring(force) end

		local node = State.graph.Nodes[idx]
		local part = State.GetPartMap(true)[idx]
		Log.Info("Debug", "hit_force BEFORE idx=%d nodeActive=%s part=%s sleeping=%s anchored=%s falling=%s active=%d",
			idx, tostring(node and node.IsActive), tostring(part and part.Name),
			tostring(part and part:GetAttribute("IsSleeping")), tostring(part and part.Anchored),
			tostring(part and part:GetAttribute("IsFalling")), #State.ActiveParts)

		local ok, err = pcall(Handler.HandleHit, State.graph, nil, idx, force, Remote.Event, State.ActiveParts)
		State.MarkDirty()
		Log.Info("Debug", "hit_force AFTER active=%d ok=%s err=%s", #State.ActiveParts, tostring(ok), tostring(err))

		if not ok then return "error: " .. tostring(err) end
		return ("Hit %d force %.1f"):format(idx, force)
	end)

	R("break_at", function(_, idx: any, pos: any, radius: any, mode: any)
		if not State.graph then return "no graph" end
		local ok, err = pcall(
			Handler.BreakAtPosition, State.graph, idx, if typeof(pos) == "Vector3" then pos else Vector3.zero,
			tonumber(radius) or 4, mode, Remote.Event, State.ActiveParts
		)
		State.MarkDirty()
		return if ok then ("BreakAtPosition idx %s OK"):format(tostring(idx)) else ("ERROR: " .. tostring(err))
	end)

	R("damage_only", function(_, idx: any, force: any)
		local g = State.graph
		if not g then return "no graph" end
		if type(idx) ~= "number" or type(force) ~= "number" then return "invalid args" end

		Mods.ForcePropagator.Propagate(g, idx, force, 40, 0.4)

		local broken = 0
		local queue = { idx }
		local seen: { [number]: boolean } = { [idx] = true }
		local head = 1
		while head <= #queue do
			local cur = queue[head]
			head += 1
			for _, e in ipairs(g.Edges[cur] or {}) do
				local dmg = e.damage_contact or 0
				for _, m in ipairs(g.Edges[e.Target] or {}) do
					if m.WeldId == e.WeldId then
						dmg = math.max(dmg, m.damage_contact or 0)
						break
					end
				end
				if dmg >= 0.999 and g.ActiveWelds[e.WeldId] ~= nil then
					g:RemoveWeld(e.WeldId)
					broken += 1
				end
				if not seen[e.Target] then
					seen[e.Target] = true
					queue[#queue + 1] = e.Target
				end
			end
		end
		State.MarkDirty()
		return ("Propagated. Forced breaks: %d"):format(broken)
	end)

	R("wake_all", function()
		local n = 0
		for _, p in ipairs(State.ActiveParts) do
			if p and p:GetAttribute("IsSleeping") and Mods.ObjectManager.WakePart(p) then n += 1 end
		end
		return ("Woke %d parts"):format(n)
	end)

	R("wake_around", function(_, pos: any, radius: any)
		if typeof(pos) ~= "Vector3" then return "invalid pos" end
		return ("Woke %d parts"):format(Mods.ObjectManager.WakeNearby(pos, tonumber(radius) or 15))
	end)

	R("wake_nearby", function(_, pos: any, radius: any)
		if typeof(pos) ~= "Vector3" then return { ok = false, error = "invalid pos" } end
		return { ok = true, woke = Mods.ObjectManager.WakeNearby(pos, tonumber(radius) or 15) }
	end)

	R("wake_object", function(_, objectId: any)
		if type(objectId) ~= "number" then return { ok = false, error = "invalid objectId: " .. tostring(objectId) } end
		for _, p in ipairs(State.ActiveParts) do
			if p and p.Parent and p:GetAttribute("ObjectId") == objectId then
				return { ok = true, woke = Mods.ObjectManager.WakePart(p), objectId = objectId }
			end
		end
		return { ok = true, woke = false, error = "objectId not found in ActiveParts" }
	end)

	R("rebuild", function() return ctx.MapService.Rebuild() end)

	R("thrust_burst", function(_, pos: any, radius: any, force: any)
		if typeof(pos) ~= "Vector3" then return "invalid pos" end
		local shape = { Type = "Sphere", CFrame = CFrame.new(pos), Radius = tonumber(radius) or 15, Falloff = "Smooth" }
		if ctx.Config.Debug.DrawOnHit then Debug.Draw.Shape(shape) end
		return ("Thrust affected %d"):format(Mods.Thrust.Shockwave(shape, tonumber(force) or 5000, nil))
	end)

	R("snapshot", function()
		local buf = Mods.FragmentManager.CaptureSnapshot()
		if not buf then return { error = "snapshot tắt" } end
		return { bytes = buffer.len(buf), stats = Mods.FragmentManager.Stats() }
	end)

	R("send_snapshot", function(player: Player)
		Mods.FragmentManager.SendSnapshot(player)
		return "sent"
	end)

	R("dump_log", function()
		local log = Mods.FragmentManager.ExportLog()
		return if log then #log else "log tắt"
	end)
end

return Actions

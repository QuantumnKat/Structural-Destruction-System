--!strict
--!native

local Inspect: any = {}

local function count(t: any): number
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

local function mirrorOf(graph: any, e: any): any?
	for _, m in ipairs(graph.Edges[e.Target] or {}) do
		if m.WeldId == e.WeldId then return m end
	end
	return nil
end

local function consistency(ctx: any): any
	local State = ctx.State
	local graph = State.graph
	local active: { BasePart } = State.ActiveParts
	local rep: any = {
		activeParts = #active, nilOrDetached = 0, duplicateInList = 0,
		missingId = 0, duplicateId = 0,
		sleepingButUnanchored = 0, awakeButAnchoredFalling = 0,
		badPosition = 0, orphanNode = 0, fallingNotActive = 0,
		samples = {},
	}
	local function note(kind: string, p: Instance?)
		rep[kind] += 1
		if #rep.samples < 8 then
			rep.samples[#rep.samples + 1] = kind .. ": " .. (if p then p:GetFullName() else "?")
		end
	end

	local inList: { [BasePart]: boolean } = {}
	local ids: { [number]: BasePart } = {}
	local yMin = (ctx.Mods.ObjectManager and -2000) or -2000

	for i = 1, #active do
		local p = active[i]
		if not p or not p.Parent then
			rep.nilOrDetached += 1
			continue
		end
		if inList[p] then note("duplicateInList", p) end
		inList[p] = true

		local oid = p:GetAttribute("ObjectId")
		if type(oid) ~= "number" then
			note("missingId", p)
		else
			if ids[oid] and ids[oid] ~= p then note("duplicateId", p) end
			ids[oid] = p
		end

		local sleeping = p:GetAttribute("IsSleeping") == true
		if sleeping and not p.Anchored then note("sleepingButUnanchored", p) end
		if not sleeping and p.Anchored and p:GetAttribute("IsFalling") == true then note("awakeButAnchoredFalling", p) end

		local pos = p.Position
		if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z or pos.Y < yMin then note("badPosition", p) end

		local pi = p:GetAttribute("PartIndex")
		if type(pi) == "number" and graph and not graph.Nodes[pi] then note("orphanNode", p) end
	end

	for _, p in pairs(State.GetPartMap(true)) do
		if p and p.Parent and p:GetAttribute("IsFalling") == true and not inList[p] then
			note("fallingNotActive", p)
		end
	end
	return rep
end

function Inspect.Init(ctx: any, Debug: any)
	local State, Mods = ctx.State, ctx.Mods
	local R = Debug.Register

	R("state", function()
		local g = State.graph
		if not g then return { ready = false } end
		local n = State.CountNodes()
		return { ready = true, parts = n, nodes = n, activeWelds = count(g.ActiveWelds), activeParts = #State.ActiveParts }
	end)

	R("list", function()
		local out = {}
		for idx, part in pairs(State.GetPartMap()) do
			if part and part.Parent then
				out[#out + 1] = {
					idx = idx, name = part.Name, hp = part:GetAttribute("HP"),
					bendingForce = part:GetAttribute("BendingForce"), isAnchor = part:GetAttribute("IsAnchor"),
				}
			end
		end
		return out
	end)

	R("damage", function(_, idx: any)
		local g = State.graph
		if not g or type(idx) ~= "number" then return {} end
		local out = {}
		for _, e in ipairs(g.Edges[idx] or {}) do
			out[#out + 1] = {
				weldId = e.WeldId, target = e.Target, damage = e.damage_contact or 0,
				sigma = e.last_sigma or 0, sigmaAllow = e.sigma_allow or 0,
				tau = e.last_tau or 0, tauAllow = e.tau_allow or 0,
			}
		end
		return out
	end)

	R("debug_edge", function(_, idx: any)
		local g = State.graph
		if not g then return { error = "no graph" } end
		local edges = g.Edges[idx]
		if not edges or #edges == 0 then return { error = "no edges for idx " .. tostring(idx) } end
		local e = edges[1]
		local m = mirrorOf(g, e)
		return {
			weldId = e.WeldId, target = e.Target, damage_primary = e.damage_contact,
			sigma_allow = e.sigma_allow, tau_allow = e.tau_allow, A_contact = e.A_contact, I_contact = e.I_contact,
			has_mirror = m ~= nil, mirror_damage = m and m.damage_contact or -1,
			has_apply_method = type(g.ApplySingleStress) == "function", active_weld = g.ActiveWelds[e.WeldId] ~= nil,
		}
	end)

	R("debug_edges_full", function(_, idx: any)
		local g = State.graph
		if not g then return {} end
		local out = {}
		for _, e in ipairs(g.Edges[idx] or {}) do
			local tgt = g.Nodes[e.Target]
			local m = mirrorOf(g, e)
			out[#out + 1] = {
				weldId = e.WeldId, target = e.Target, targetActive = tgt and tgt.IsActive or false,
				targetName = tgt and tgt.Name or "?", active_weld = g.ActiveWelds[e.WeldId] ~= nil,
				damage = e.damage_contact or 0, mirrorDamage = m and m.damage_contact or -1,
			}
		end
		return out
	end)

	R("propagator_check", function(_, idx: any)
		local g = State.graph
		if not g then return { error = "no graph" } end
		local i = if type(idx) == "number" then idx else 8
		local edges = g.Edges[i]
		if not edges or #edges == 0 then return { error = "no edges at " .. i } end
		local maxed = false
		for _, e in ipairs(edges) do
			if (e.damage_contact or 0) >= 0.999 then maxed = true break end
		end
		return {
			idx = i, has_apply_method = type(g.ApplySingleStress) == "function",
			edge_count = #edges, edges_at_max_damage = maxed, total_active_welds = count(g.ActiveWelds),
		}
	end)

	R("node_debug", function()
		local g = State.graph
		if not g then return {} end
		local map = State.GetPartMap(true)
		local out = {}
		for i, node in pairs(g.Nodes) do
			local p = map[i]
			out[#out + 1] = {
				idx = i, name = node.Name, isActive = node.IsActive, isAnchor = node.IsAnchor,
				hasPart = p ~= nil and p.Parent ~= nil, anchored = p and p.Anchored or nil,
				isFalling = p and p:GetAttribute("IsFalling") or nil,
			}
		end
		return out
	end)

	R("grounded_debug", function()
		local g = State.graph
		if not g then return {} end
		local out = {}
		for i in pairs(g:GetGroundedNodes()) do out[#out + 1] = i end
		return out
	end)

	R("grounded_dump", function()
		local g = State.graph
		if not g then return {} end
		local grounded = g:GetGroundedNodes()
		local out = { groundedList = {}, notGroundedList = {} }
		for idx, node in pairs(g.Nodes) do
			if node.IsActive then
				table.insert(if grounded[idx] then out.groundedList else out.notGroundedList, idx)
			end
		end
		return out
	end)

	R("grounded_bfs_debug", function()
		local g = State.graph
		if not g then return {} end
		local nodes, edges, active = g.Nodes, g.Edges, g.ActiveWelds
		local out: any = { errors = {}, anchors = {}, reached = {} }
		local grounded: { [number]: boolean } = {}
		local queue: { number } = {}
		for i, n in pairs(nodes) do
			if n.IsActive and n.IsAnchor then
				out.anchors[#out.anchors + 1] = i
				grounded[i] = true
				queue[#queue + 1] = i
			end
		end
		local head = 1
		while head <= #queue do
			local cur = queue[head]
			head += 1
			for _, e in ipairs(edges[cur] or {}) do
				if active[e.WeldId] ~= nil then
					local t = nodes[e.Target]
					if not grounded[e.Target] and t and t.IsActive then
						grounded[e.Target] = true
						queue[#queue + 1] = e.Target
					end
				else
					out.errors[#out.errors + 1] = ("[weld %d] active=nil"):format(e.WeldId)
				end
			end
		end
		for i in pairs(grounded) do out.reached[#out.reached + 1] = i end
		out.officialCount = count(g:GetGroundedNodes())
		out.manualCount = #out.reached
		return out
	end)

	R("weld_debug", function()
		local g = State.graph
		if not g then return {} end
		local seen: { [number]: boolean } = {}
		local out = {}
		for a, edges in pairs(g.Edges) do
			for _, e in ipairs(edges) do
				if g.ActiveWelds[e.WeldId] ~= nil and not seen[e.WeldId] then
					seen[e.WeldId] = true
					local an, bn = g.Nodes[a], g.Nodes[e.Target]
					out[#out + 1] = {
						weldId = e.WeldId, a = a, b = e.Target, aName = an and an.Name or "?", bName = bn and bn.Name or "?",
						aActive = an and an.IsActive, bActive = bn and bn.IsActive,
					}
				end
			end
		end
		return out
	end)

	R("part_attrs", function(_, idx: any)
		local g = State.graph
		if not g then return { error = "no graph" } end
		if type(idx) ~= "number" then return { error = "invalid idx" } end
		local n = g.Nodes[idx]
		if not n then return { error = "no node" } end
		return {
			name = n.Name, compressionStrength = n.CompressionStrength, bendingForce = n.BendingForce,
			tensileStrength = n.TensileStrength, mass = n.Mass,
		}
	end)

	R("edges_stress", function()
		local g = State.graph
		if not g then return {} end
		local out = {}
		for a, edges in pairs(g.Edges) do
			for _, e in ipairs(edges) do
				if a < e.Target then
					local an, bn = g.Nodes[a], g.Nodes[e.Target]
					out[#out + 1] = {
						weldId = e.WeldId, a = a, b = e.Target, aName = an and an.Name or "?", bName = bn and bn.Name or "?",
						sigma = e.last_sigma, sigmaAllow = e.sigma_allow, tau = e.last_tau, tauAllow = e.tau_allow,
						damage = e.damage_contact, active = g.ActiveWelds[e.WeldId] ~= nil,
						ratio = (e.sigma_allow > 0 and e.last_sigma / e.sigma_allow) or 0,
					}
				end
			end
		end
		return out
	end)

	R("sleep_stats", function()
		local sleeping, awake = 0, 0
		for _, p in ipairs(State.ActiveParts) do
			if p and p.Parent then
				if p:GetAttribute("IsSleeping") then sleeping += 1 else awake += 1 end
			end
		end
		return { sleeping = sleeping, active = awake, total = #State.ActiveParts }
	end)

	R("sleeping_list", function()
		local out = {}
		for _, p in ipairs(State.ActiveParts) do
			if p and p.Parent and p:GetAttribute("IsSleeping") then
				out[#out + 1] = {
					idx = p:GetAttribute("PartIndex"), objectId = p:GetAttribute("ObjectId"), name = p.Name,
					position = { p.Position.X, p.Position.Y, p.Position.Z },
				}
			end
		end
		return out
	end)

	R("consistency", function() return consistency(ctx) end)

	R("audit", function(_, fix: any)
		return Mods.PartIds.Audit(fix == true)
	end)

	R("ids", function() return Mods.PartIds.Stats() end)

	R("events", function(_, n: any)
		local log = Mods.FragmentManager.GetLog()
		if not log then return { error = "event log tắt (FragmentConf.Log.Enabled)" } end
		local want = if type(n) == "number" then math.clamp(n, 1, 200) else 30
		local ring: { any } = {}
		log:ForEach(function(_seq: number, kind: number, buf: buffer, off: number)
			ring[#ring + 1] = Mods.FragmentManager.DecodeEvent(kind, buf, off)
			if #ring > want then table.remove(ring, 1) end
		end)
		return { stats = log:Stats(), tail = ring }
	end)
end

return Inspect

--!strict
-- EditorSync: refactor-v1
--!native
local mathmax = math.max
local function edgeSticks(e: any, a: any, b: any, va: Vector3, vb: Vector3, C: any): boolean
	local dmg: number = e.damage_contact
	if dmg >= C.MaxDamageToStick then return false end
	local bind = e.sigma_allow * e.A_contact * (1 - dmg) * C.BindScale
	local ma, mb = a.Mass, b.Mass
	local meff = ma * mb / mathmax(ma + mb, 1e-6)
	local rel = (va - vb).Magnitude
	return meff * rel / C.TearTime <= bind
end

local function rigidState(list: { number }, nodes: any, vel: { [number]: Vector3 }): (number, Vector3, Vector3, Vector3)
	local M = 0
	local com = Vector3.zero
	local vs = Vector3.zero
	for i = 1, #list do
		local node = nodes[list[i]]
		local m: number = node.Mass
		M += m
		com += node.Position * m
		vs += vel[list[i]] * m
	end
	if M < 1e-6 then M = 1e-6 end
	com = com / M
	local vCom = vs / M
	local Lsum = Vector3.zero
	local I = 0
	for i = 1, #list do
		local node = nodes[list[i]]
		local m: number = node.Mass
		local r: Vector3 = node.Position - com
		Lsum += r:Cross(vel[list[i]] - vCom) * m
		I += m * r:Dot(r)
	end
	return M, com, vCom, Lsum / mathmax(I, 1e-3)
end

local function splitBig(members: { number }, maxSize: number, nodes: any, edges: any): { { number } }
	if #members <= maxSize then return { members } end

	local inComp: { [number]: boolean } = {}
	local mn = Vector3.new(math.huge, math.huge, math.huge)
	local mx = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, idx in ipairs(members) do
		inComp[idx] = true
		local p: Vector3 = nodes[idx].Position
		mn = mn:Min(p)
		mx = mx:Max(p)
	end
	local ext = mx - mn
	local axis = if ext.X >= ext.Y and ext.X >= ext.Z then Vector3.xAxis
		elseif ext.Y >= ext.Z then Vector3.yAxis else Vector3.zAxis

	local sorted = table.clone(members)
	table.sort(sorted, function(a, b)
		return nodes[a].Position:Dot(axis) < nodes[b].Position:Dot(axis)
	end)

	local out: { { number } } = {}
	local assigned: { [number]: boolean } = {}
	for _, start in ipairs(sorted) do
		if not assigned[start] then
			local chunk: { number } = { start }
			assigned[start] = true
			local head = 1
			while head <= #chunk and #chunk < maxSize do
				local cur = chunk[head]
				head += 1
				local ce = edges[cur]
				if ce then
					for k = 1, #ce do
						local t = ce[k].Target
						if inComp[t] and not assigned[t] and #chunk < maxSize then
							assigned[t] = true
							chunk[#chunk + 1] = t
						end
					end
				end
			end
			out[#out + 1] = chunk
		end
	end
	return out
end


return { EdgeSticks = edgeSticks, RigidState = rigidState, SplitBig = splitBig }

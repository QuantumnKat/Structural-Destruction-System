--!strict
-- EditorSync: refactor-v1
--!native
return function(deps: any)
local S, Conf = deps.State, deps.Config
local mark, ensureId = deps.Mark, deps.EnsureId
local mathmax, mathmin, random = math.max, math.min, math.random
local mathModule = require(script.Parent.FragmentMath)
local edgeSticks, rigidState, splitBig = mathModule.EdgeSticks, mathModule.RigidState, mathModule.SplitBig
local function createWeld(p0: BasePart, p1: BasePart)
 local w = Instance.new("WeldConstraint")
 w.Name = "FragWeld"; w.Part0 = p0; w.Part1 = p1; w.Parent = p1
end
local FragmentManager = {}
function FragmentManager.PlanFragments(idxs: { number }, partMap: { [number]: BasePart }, info: any): number
	if not S.inited or #idxs == 0 then return 0 end
	local graph = S.graph
	local nodes, edges = graph.Nodes, graph.Edges
	local T, L, C = Conf.Trigger, Conf.Launch, Conf.Cluster

	local list: { number } = {}
	local parts: { [number]: BasePart } = {}
	local inSet: { [number]: boolean } = {}
	local partSet: { [BasePart]: boolean } = {}
	local totalMass = 0
	for i = 1, #idxs do
		local idx = idxs[i]
		local node, part = nodes[idx], partMap[idx]
		if node and part and part.Parent and not inSet[idx] then
			inSet[idx] = true
			list[#list + 1] = idx
			parts[idx] = part
			partSet[part] = true
			totalMass += node.Mass
			mark(idx, 1)
		end
	end
	local n = #list
	if n == 0 then return 0 end
	if S.log then S.log:Collapse(n) end

	local force: number = info.Force or 0
	if n < T.MinCollapseParts or totalMass < T.MinCollapseMass or force < T.MinForce then
		return 0
	end

	local fMap: { [number]: number } = {}
	if info.Impacts then
		for _, im in ipairs(info.Impacts) do
			local f = fMap[im.idx]
			if not f or im.force > f then fMap[im.idx] = im.force end
		end
	end
	local dirMap: { [number]: Vector3 } = {}
	if info.Hits then
		for _, h in ipairs(info.Hits) do dirMap[h.idx] = h.dir end
	end
	local center: Vector3 = info.Center
	local vel: { [number]: Vector3 } = {}
	for _, idx in ipairs(list) do
		local node = nodes[idx]
		local dir = dirMap[idx]
		if not dir then
			local d: Vector3 = node.Position - center
			dir = if d.Magnitude > 1e-3 then d.Unit else Vector3.yAxis
		end
		local speed = mathmin(L.MaxSpeed, (fMap[idx] or 0) / mathmax(node.Mass, 1e-3) * L.VelocityPerForce)
		local v: Vector3 = dir + Vector3.yAxis * L.UpwardBias
		if v.Magnitude > 1e-3 and speed > 0 then
			v = v.Unit * speed
			v += Vector3.new(random() - 0.5, random() - 0.5, random() - 0.5) * (speed * L.Jitter)
		else
			v = Vector3.zero
		end
		vel[idx] = v
	end

	for _, idx in ipairs(list) do
		local part = parts[idx]
		part.Anchored = false
		part:SetAttribute("IsSleeping", false)
		ensureId(part)
		local joints = part:GetJoints()
		for j = 1, #joints do
			local w = joints[j]
			if w:IsA("WeldConstraint") then
				local a, b = w.Part0, w.Part1
				if a and b and partSet[a] and partSet[b] then
					w:Destroy()
				end
			end
		end
	end

	local visited: { [number]: boolean } = {}
	local comps: { { members: { number }, dmgSum: number, ec: number } } = {}
	for _, start in ipairs(list) do
		if visited[start] then continue end
		local comp: { number } = {}
		local q: { number } = { start }
		visited[start] = true
		local head = 1
		local dmgSum, ec = 0, 0
		while head <= #q do
			local cur = q[head]
			head += 1
			comp[#comp + 1] = cur
			local ce = edges[cur]
			if ce then
				for k = 1, #ce do
					local e = ce[k]
					local tgt = e.Target
					if inSet[tgt] and not visited[tgt] and edgeSticks(e, nodes[cur], nodes[tgt], vel[cur], vel[tgt], C) then
						visited[tgt] = true
						q[#q + 1] = tgt
						dmgSum += e.damage_contact
						ec += 1
					end
				end
			end
		end
		comps[#comps + 1] = { members = comp, dmgSum = dmgSum, ec = ec }
	end

	local weldBudget: number = C.MaxWeldsPerEvent
	local voxel: number = (graph.Config and graph.Config.BASE_VOXEL_SIZE) or 2
	local fragCount = 0

	local function applyCluster(members: { number }, avgDmg: number)
		local count = #members
		local inCl: { [number]: boolean } = {}
		for _, idx in ipairs(members) do inCl[idx] = true end

		local M, com, vCom = rigidState(members, nodes, vel)
		local noWeldMass = 0
		for _, idx in ipairs(members) do
			if C.NoWeldMaterials[parts[idx].Material.Name] then
				noWeldMass += nodes[idx].Mass
			end
		end

		local doWeld = count >= C.MinWeldParts
			and C.WeldMode ~= "None"
			and weldBudget >= count - 1
			and noWeldMass <= M * 0.5
			and avgDmg <= C.MaxAvgDamage

		if doWeld and C.ShatterEnergyRatio > 0 then
			local erel, ebind = 0, 0
			for _, idx in ipairs(members) do
				local dv: Vector3 = vel[idx] - vCom
				erel += 0.5 * nodes[idx].Mass * dv:Dot(dv)
				local ce = edges[idx]
				if ce then
					for k = 1, #ce do
						local e = ce[k]
						if inCl[e.Target] and idx < e.Target then
							ebind += e.sigma_allow * e.A_contact * (1 - e.damage_contact) * voxel
						end
					end
				end
			end
			if erel > ebind * C.ShatterEnergyRatio then
				doWeld = false
			end
		end

		local inGroup: { [number]: boolean } = {}
		if doWeld then
			local rootIdx = members[1]
			local best = math.huge
			for _, idx in ipairs(members) do
				local d = (nodes[idx].Position - com).Magnitude
				if d < best then
					best = d
					rootIdx = idx
				end
			end

			local group: { number } = { rootIdx }
			local seen: { [number]: boolean } = { [rootIdx] = true }
			local welds = 0
			if C.WeldMode == "Hub" then
				for _, idx in ipairs(members) do
					if idx ~= rootIdx then
						createWeld(parts[rootIdx], parts[idx])
						group[#group + 1] = idx
						welds += 1
					end
				end
			else
				local head = 1
				while head <= #group do
					local cur = group[head]
					head += 1
					local ce = edges[cur]
					if ce then
						for k = 1, #ce do
							local e = ce[k]
							local t = e.Target
							if inCl[t] and not seen[t] and edgeSticks(e, nodes[cur], nodes[t], vel[cur], vel[t], C) then
								seen[t] = true
								createWeld(parts[cur], parts[t])
								group[#group + 1] = t
								welds += 1
							end
						end
					end
				end
			end
			weldBudget -= welds

			if #group >= 2 then
				local gM, gCom, gV, gW = rigidState(group, nodes, vel)
				if gW.Magnitude > L.MaxSpin then gW = gW.Unit * L.MaxSpin end
				local fid = S.nextFid
				S.nextFid += 1
				for _, idx in ipairs(group) do
					inGroup[idx] = true
					local p = parts[idx]
					p:SetAttribute("FragmentId", fid)
					p.AssemblyLinearVelocity = gV
					p.AssemblyAngularVelocity = gW
				end
				parts[rootIdx]:SetAttribute("FragmentRoot", true)
				fragCount += 1
				if S.log then S.log:Fragment(fid, #group, true, gM, gCom, gV) end
			end
		end

		for _, idx in ipairs(members) do
			if not inGroup[idx] then
				local p = parts[idx]
				p.AssemblyLinearVelocity = vel[idx]
				p.AssemblyAngularVelocity = Vector3.new(random() - 0.5, random() - 0.5, random() - 0.5) * (L.MaxSpin * 0.3)
			end
		end
	end

	for _, comp in ipairs(comps) do
		local avgDmg = if comp.ec > 0 then comp.dmgSum / comp.ec else 0
		for _, chunk in ipairs(splitBig(comp.members, C.MaxPartsPerCluster, nodes, edges)) do
			applyCluster(chunk, avgDmg)
		end
	end

	return fragCount
end

return FragmentManager.PlanFragments
end

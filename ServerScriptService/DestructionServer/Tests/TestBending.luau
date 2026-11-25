--!strict
--!native

local Workspace      = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local ServerFolder   = ServerScriptService:WaitForChild("DestructionServer")
local StructureGraph = require(ServerFolder.Destruction.Structure.StructureGraph)

local SANDBOX_NAME = "TestSandbox"



local function getSandbox(): Folder
	local s = Workspace:FindFirstChild(SANDBOX_NAME)
	if not s then
		s = Instance.new("Folder")
		s.Name = SANDBOX_NAME
		s.Parent = Workspace
	end
	return s :: Folder
end

local function clearSandbox()
	local s = Workspace:FindFirstChild(SANDBOX_NAME)
	if s then s:Destroy() end
end

local function makePart(
	parent: Instance, size: Vector3, cf: CFrame,
	material: Enum.Material?, isAnchor: boolean?
): Part
	local p = Instance.new("Part")
	p.Name       = (isAnchor and "Anchor_" or "Part_") .. tostring(math.random(1, 99999))
	p.Size       = size
	p.CFrame     = cf
	p.Material   = material or Enum.Material.Concrete
	p.Anchored   = true
	p.CanCollide = false
	p.Parent     = parent
	p:SetAttribute("IsAnchor", isAnchor or false)
	p:SetAttribute("IsDestructible", true)
	return p
end

local function addWeld(a: Part, b: Part): WeldConstraint
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
	return w
end

local function buildGraphFromSandbox(sandbox: Instance): (any, { [number]: Part })
	local parts: { Part } = {}
	for _, d in ipairs(sandbox:GetDescendants()) do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	for i, p in ipairs(parts) do p:SetAttribute("PartIndex", i) end

	local physicalPartMap: { [number]: Part } = {}
	for i, p in ipairs(parts) do physicalPartMap[i] = p end

	local payload: any = { Parts = {}, Welds = {} }
	for i, p in ipairs(parts) do
		payload.Parts[i] = {
			Name                = p.Name,
			CFrame              = p.CFrame,
			Size                = p.Size,
			Mass                = p:GetAttribute("Mass") or (p.Size.X * p.Size.Y * p.Size.Z * 0.7),
			HP                  = p:GetAttribute("HP") or 100,
			Category            = p:GetAttribute("IsAnchor") and 3 or 1,
			IsAnchor            = p:GetAttribute("IsAnchor") == true,
			TensileStrength     = p:GetAttribute("TensileStrength") or 150,
			BendingForce        = p:GetAttribute("BendingForce") or 300,
			CompressionStrength = p:GetAttribute("CompressionStrength") or 800,
			ForceTransmission   = 1.0,
		}
	end

	local weldId = 1
	for _, p in ipairs(parts) do
		local idx = p:GetAttribute("PartIndex")
		for _, c in ipairs(p:GetChildren()) do
			if c:IsA("WeldConstraint") and c.Part0 == p then
				local other = c.Part1
				local otherIdx = other and other:GetAttribute("PartIndex")
				if otherIdx and idx < otherIdx then
					payload.Welds[weldId] = {
						PartA = idx, PartB = otherIdx, Constraint = c,
					}
					weldId += 1
				end
			end
		end
	end

	return StructureGraph.new(payload), physicalPartMap
end

local function countParts(folder: Instance): number
	local n = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and d.Parent then n += 1 end
	end
	return n
end

local function report(pass: boolean, msg: string): boolean
	print(("[%s] %s"):format(pass and "PASS" or "FAIL", msg))
	return pass
end



local Tests = {}

function Tests.T1_PillarStable()
	print("\n=== T1: Pillar stable ===")
	clearSandbox()
	local sb = getSandbox()

	local pillar = makePart(sb, Vector3.new(2, 10, 2),
		CFrame.new(0, 5, 0), Enum.Material.Concrete, true)
	pillar:SetAttribute("CompressionStrength", 2000)
	pillar:SetAttribute("Mass", 100)

	local graph = buildGraphFromSandbox(sb)
	for _ = 1, 20 do graph:Tick(1/60) end

	local n = countParts(sb)
	return report(n == 1, ("T1 parts remain = %d (expect 1)"):format(n))
end

function Tests.T2_CantileverBreak()
	print("\n=== T2: Cantilever breaks ===")
	clearSandbox()
	local sb = getSandbox()

	local anchor = makePart(sb, Vector3.new(2, 2, 2),
		CFrame.new(0, 0, 0), Enum.Material.Concrete, true)
	anchor:SetAttribute("BendingForce", 1000)
	anchor:SetAttribute("Mass", 100)

	local beam = makePart(sb, Vector3.new(10, 1, 1),
		CFrame.new(6, 0, 0), Enum.Material.Wood, false)
	beam:SetAttribute("BendingForce", 100)
	beam:SetAttribute("TensileStrength", 80)
	beam:SetAttribute("Mass", 500)

	addWeld(anchor, beam)

	local graph = buildGraphFromSandbox(sb)
	local beamIdx = beam:GetAttribute("PartIndex")

	for _ = 1, 200 do
		graph:Tick(1/60)
		if not graph:GetGroundedNodes()[beamIdx] then break end
	end

	local grounded = graph:GetGroundedNodes()[beamIdx] == true
	return report(not grounded,
		("T2 cantilever breaks: grounded=%s (expect false)"):format(tostring(grounded)))
end

function Tests.T3_DoubleAnchorStable()
	print("\n=== T3: Double-anchor stable (R1) ===")
	clearSandbox()
	local sb = getSandbox()

	local a1 = makePart(sb, Vector3.new(2, 2, 2),
		CFrame.new(-6, 0, 0), Enum.Material.Concrete, true)
	local a2 = makePart(sb, Vector3.new(2, 2, 2),
		CFrame.new(6, 0, 0), Enum.Material.Concrete, true)

	local beam = makePart(sb, Vector3.new(10, 1, 1),
		CFrame.new(0, 0, 0), Enum.Material.Wood, false)
	beam:SetAttribute("BendingForce", 5000)
	beam:SetAttribute("TensileStrength", 5000)
	beam:SetAttribute("Mass", 500)

	addWeld(a1, beam)
	addWeld(a2, beam)

	local graph = buildGraphFromSandbox(sb)
	local beamIdx = beam:GetAttribute("PartIndex")

	for _ = 1, 500 do graph:Tick(1/60) end

	local grounded = graph:GetGroundedNodes()[beamIdx] == true
	return report(grounded,
		("T3 beam stays (R1): grounded=%s (expect true)"):format(tostring(grounded)))
end

function Tests.T4_CompressionFailure()
	print("\n=== T4: Compression failure ===")
	clearSandbox()
	local sb = getSandbox()

	local base = makePart(sb, Vector3.new(4, 2, 4),
		CFrame.new(0, 1, 0), Enum.Material.Concrete, true)

	local col = makePart(sb, Vector3.new(1, 10, 1),
		CFrame.new(0, 7, 0), Enum.Material.Wood, false)
	col:SetAttribute("CompressionStrength", 50)
	col:SetAttribute("Mass", 5000)

	local load = makePart(sb, Vector3.new(8, 8, 8),
		CFrame.new(0, 20, 0), Enum.Material.Metal, false)
	load:SetAttribute("Mass", 10000)

	addWeld(base, col)
	addWeld(col, load)

	local graph = buildGraphFromSandbox(sb)
	for _ = 1, 500 do graph:Tick(1/60) end

	local g = graph:GetGroundedNodes()
	local colLost  = g[col:GetAttribute("PartIndex")] ~= true
	local loadLost = g[load:GetAttribute("PartIndex")] ~= true

	return report(colLost or loadLost,
		("T4 col or load fails: col_lost=%s load_lost=%s"):format(
			tostring(colLost), tostring(loadLost)))
end

function Tests.T5_FloorCollapseNeighborHolds()
	print("\n=== T5: Floor collapse, neighbor holds (spec §5) ===")
	clearSandbox()
	local sb = getSandbox()

	local wall = makePart(sb, Vector3.new(2, 20, 2),
		CFrame.new(-10, 10, 0), Enum.Material.Concrete, true)
	wall:SetAttribute("BendingForce", 5000)
	wall:SetAttribute("TensileStrength", 5000)

	local s1 = makePart(sb, Vector3.new(4, 1, 4),
		CFrame.new(-6, 0, 0), Enum.Material.Wood, false)
	s1:SetAttribute("BendingForce", 2000)
	s1:SetAttribute("TensileStrength", 2000)
	s1:SetAttribute("Mass", 100)

	local s2 = makePart(sb, Vector3.new(4, 1, 4),
		CFrame.new(-2, 0, 0), Enum.Material.Wood, false)
	s2:SetAttribute("BendingForce", 50)
	s2:SetAttribute("TensileStrength", 50)
	s2:SetAttribute("Mass", 500)

	local s3 = makePart(sb, Vector3.new(4, 1, 4),
		CFrame.new(2, 0, 0), Enum.Material.Wood, false)
	s3:SetAttribute("BendingForce", 50)
	s3:SetAttribute("TensileStrength", 50)
	s3:SetAttribute("Mass", 500)

	addWeld(wall, s1)
	addWeld(s1, s2)
	addWeld(s2, s3)

	local graph = buildGraphFromSandbox(sb)
	for _ = 1, 500 do graph:Tick(1/60) end

	local g = graph:GetGroundedNodes()
	local s1G = g[s1:GetAttribute("PartIndex")] == true
	local s2G = g[s2:GetAttribute("PartIndex")] == true
	local s3G = g[s3:GetAttribute("PartIndex")] == true

	print(("[T5] s1=%s s2=%s s3=%s"):format(tostring(s1G), tostring(s2G), tostring(s3G)))
	return report(s1G and (not s2G or not s3G),
		("T5 s1 stays + s2/s3 falls"))
end

function Tests.T6_DamageAccumulates()
	print("\n=== T6: Damage accumulates (R3) ===")
	clearSandbox()
	local sb = getSandbox()

	local anchor = makePart(sb, Vector3.new(2, 2, 2),
		CFrame.new(0, 0, 0), Enum.Material.Concrete, true)
	local beam = makePart(sb, Vector3.new(10, 1, 1),
		CFrame.new(6, 0, 0), Enum.Material.Wood, false)
	beam:SetAttribute("BendingForce", 100)
	beam:SetAttribute("Mass", 500)
	addWeld(anchor, beam)

	local graph = buildGraphFromSandbox(sb)
	local beamIdx = beam:GetAttribute("PartIndex")

	graph:Tick(1/60)
	local g1 = graph:GetGroundedNodes()[beamIdx] == true

	for _ = 1, 300 do graph:Tick(1/60) end
	local gN = graph:GetGroundedNodes()[beamIdx] == true

	print(("[T6] after_1_tick=%s after_300_ticks=%s"):format(tostring(g1), tostring(gN)))
	return report(g1 and not gN, "T6 no break at tick 1, break by tick 300 (R3)")
end

function Tests.T7_PillarHoldsPart()
	print("\n=== T7: Pillar holds part (spec §6) ===")
	clearSandbox()
	local sb = getSandbox()

	local pillar = makePart(sb, Vector3.new(2, 20, 2),
		CFrame.new(0, 10, 0), Enum.Material.Concrete, true)
	pillar:SetAttribute("CompressionStrength", 5000)
	pillar:SetAttribute("BendingForce", 5000)

	local beam = makePart(sb, Vector3.new(8, 1, 1),
		CFrame.new(4, 20, 0), Enum.Material.Wood, false)
	beam:SetAttribute("BendingForce", 2000)
	beam:SetAttribute("Mass", 500)

	addWeld(pillar, beam)

	local graph = buildGraphFromSandbox(sb)
	local beamIdx = beam:GetAttribute("PartIndex")

	for _ = 1, 500 do graph:Tick(1/60) end

	local grounded = graph:GetGroundedNodes()[beamIdx] == true
	return report(grounded,
		("T7 pillar holds: grounded=%s (expect true)"):format(tostring(grounded)))
end



local function runAllTests()
	print("\n" .. string.rep("═", 60))
	print("BENDING TEST SUITE")
	print(string.rep("═", 60))

	local order = {
		"T1_PillarStable",
		"T2_CantileverBreak",
		"T3_DoubleAnchorStable",
		"T4_CompressionFailure",
		"T5_FloorCollapseNeighborHolds",
		"T6_DamageAccumulates",
		"T7_PillarHoldsPart",
	}

	local passed, failed = 0, 0
	for _, name in ipairs(order) do
		local fn = Tests[name]
		if fn then
			local ok, result = pcall(fn)
			if not ok then
				print(("[ERROR] %s: %s"):format(name, tostring(result)))
				failed += 1
			elseif result then
				passed += 1
			else
				failed += 1
			end
			task.wait(0.2)
		end
	end

	print("\n" .. string.rep("═", 60))
	print(("SUMMARY: %d passed, %d failed, %d total"):format(passed, failed, passed + failed))
	print(string.rep("═", 60))

	clearSandbox()
end

if script:GetAttribute("_RunTests") == true then
	task.spawn(runAllTests)
else
	print("[TestBending] Set attribute _RunTests = true on this script to run")
end

return Tests

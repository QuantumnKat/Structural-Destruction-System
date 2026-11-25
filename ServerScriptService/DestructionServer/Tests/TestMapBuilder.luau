--!strict
--!native

local Workspace = game:GetService("Workspace")
local TestMapBuilder = {}

local MAP_NAME = "Map"


local BASE_Y       = 2
local BASE_H       = 3
local SLAB_THICK   = 0.4
local WALL_T       = 0.4
local PILLAR_SIZE  = 1.5
local PILLAR_HALF  = PILLAR_SIZE / 2
local FLOOR_H      = 6

local PODIUM_W     = 48
local PODIUM_D     = 40
local PODIUM_FLOORS = 2

local TOWER_W      = 36
local TOWER_D      = 28
local TOWER_FLOORS = 10
local TOTAL_FLOORS = PODIUM_FLOORS + TOWER_FLOORS


local FLOOR_SLAB   = { 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 0 }

local FLOOR_WALL   = { 2, 2, 2, 2, 1, 1, 0, 0, 0, 0, 0, 0 }


local SITE_X0, SITE_X1 = -46, 46
local SITE_Z0, SITE_Z1 = -42, 38
local GATE_W = 8


local function getMapFolder(): Folder
	local cam = Workspace:FindFirstChild("Camera")
	local parent: Instance = cam or Workspace
	local map = parent:FindFirstChild(MAP_NAME)
	if not map then
		map = Instance.new("Folder")
		map.Name = MAP_NAME
		map.Parent = parent
	end
	return map :: Folder
end

local function makePart(opts: any): Part
	local p = Instance.new("Part")
	p.Name          = opts.name or "Part"
	p.Size          = opts.size or Vector3.one * 2
	p.CFrame        = opts.cframe or CFrame.new()
	p.Material      = opts.material or Enum.Material.Concrete
	p.Color         = opts.color or Color3.new(0.6, 0.6, 0.6)
	p.Anchored      = true
	p.CanCollide    = true
	p.TopSurface    = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(opts.attrs or {}) do
		p:SetAttribute(k, v)
	end
	return p
end

local function box(map: Folder, name: string, size: Vector3, cf: CFrame,
	material: Enum.Material, color: Color3, attrs: any?): Part
	local p = makePart({ name=name, size=size, cframe=cf, material=material, color=color, attrs=attrs })
	p.Parent = map
	return p
end




local ATTRS = {
	Foundation = { IsAnchor = true, IsDestructible = false, HP = 999999, Mass = 999999,
		CompressionStrength = 999999, BendingForce = 999999, TensileStrength = 999999 },
	ConcretePillar = { IsAnchor = false, IsDestructible = true, HP = 40000, Mass = 2000,
		CompressionStrength = 500000, BendingForce = 200000, TensileStrength = 120000,
		OnDisconnect = "Auto", BreakRadius = 4 },
	ConcreteSlab = { IsAnchor = false, IsDestructible = true, HP = 30000, Mass = 3000,
		CompressionStrength = 600000, BendingForce = 400000, TensileStrength = 150000,
		OnDisconnect = "Detach", BreakRadius = 5 },
	SteelBeam = { IsAnchor = false, IsDestructible = true, HP = 35000, Mass = 1200,
		CompressionStrength = 400000, BendingForce = 300000, TensileStrength = 250000,
		OnDisconnect = "Auto", BreakRadius = 3 },
	WallBlock = { IsAnchor = false, IsDestructible = true, HP = 12000, Mass = 800,
		CompressionStrength = 200000, BendingForce = 100000, TensileStrength = 50000,
		OnDisconnect = "Break", BreakRadius = 2.5 },
	Scaffold = { IsAnchor = false, IsDestructible = true, HP = 3000, Mass = 200,
		CompressionStrength = 25000, BendingForce = 18000, TensileStrength = 12000,
		OnDisconnect = "Detach", BreakRadius = 2 },
	Rebar = { IsAnchor = false, IsDestructible = true, HP = 1500, Mass = 80,
		CompressionStrength = 30000, BendingForce = 25000, TensileStrength = 20000,
		OnDisconnect = "Break", BreakRadius = 1.5 },
	MaterialPile = { IsAnchor = false, IsDestructible = true, HP = 5000, Mass = 400,
		CompressionStrength = 100000, BendingForce = 50000, TensileStrength = 30000,
		OnDisconnect = "Detach", BreakRadius = 2 },
	Tarp = { IsAnchor = false, IsDestructible = true, HP = 500, Mass = 50,
		CompressionStrength = 1000, BendingForce = 500, TensileStrength = 300,
		OnDisconnect = "Detach", BreakRadius = 2 },
	Crane = { IsAnchor = false, IsDestructible = true, HP = 80000, Mass = 5000,
		CompressionStrength = 800000, BendingForce = 500000, TensileStrength = 300000,
		OnDisconnect = "Auto", BreakRadius = 6 },
	Glass = { IsAnchor = false, IsDestructible = true, HP = 200, Mass = 30,
		CompressionStrength = 5000, BendingForce = 1000, TensileStrength = 500,
		OnDisconnect = "Shatter", ShatterAirPercent = 0.85,
		BreakRadius = 4, MaxDebrisPerPart = 32 },
	Railing = { IsAnchor = false, IsDestructible = true, HP = 3000, Mass = 100,
		CompressionStrength = 15000, BendingForce = 8000, TensileStrength = 5000,
		OnDisconnect = "Detach", BreakRadius = 1.5 },
	SiteLight = { IsAnchor = false, IsDestructible = true, HP = 4000, Mass = 300,
		CompressionStrength = 30000, BendingForce = 15000, TensileStrength = 8000,
		OnDisconnect = "Detach", BreakRadius = 2 },
	Container = { IsAnchor = false, IsDestructible = true, HP = 15000, Mass = 1500,
		CompressionStrength = 200000, BendingForce = 120000, TensileStrength = 60000,
		OnDisconnect = "Detach", BreakRadius = 3 },
	Sign = { IsAnchor = false, IsDestructible = true, HP = 800, Mass = 40,
		CompressionStrength = 5000, BendingForce = 2000, TensileStrength = 1500,
		OnDisconnect = "Detach", BreakRadius = 1.5 },
	Silo = { IsAnchor = false, IsDestructible = true, HP = 25000, Mass = 4000,
		CompressionStrength = 300000, BendingForce = 200000, TensileStrength = 100000,
		OnDisconnect = "Auto", BreakRadius = 4 },
	PipeStack = { IsAnchor = false, IsDestructible = true, HP = 6000, Mass = 500,
		CompressionStrength = 50000, BendingForce = 30000, TensileStrength = 20000,
		OnDisconnect = "Detach", BreakRadius = 2.5 },
	Formwork = { IsAnchor = false, IsDestructible = true, HP = 4000, Mass = 300,
		CompressionStrength = 30000, BendingForce = 20000, TensileStrength = 12000,
		OnDisconnect = "Detach", BreakRadius = 2 },
}

local CONCRETE_STYLE = { material = Enum.Material.Concrete, color = Color3.fromRGB(160,160,155), attrs = ATTRS.WallBlock }
local GLASS_STYLE    = { material = Enum.Material.Glass,    color = Color3.fromRGB(150,200,230), attrs = ATTRS.Glass }

local function buildWallSide(map: Folder, name: string, cf: CFrame,
	length: number, height: number,
	openW: number, openH: number, openY: number,
	style: any, glassStyle: any, isDoor: boolean?)
	local halfOpen = openW / 2
	local sideW    = (length - openW) / 2
	local function seg(x: number, y: number, sx: number, sy: number)
		box(map, name, Vector3.new(sx, sy, WALL_T),
			cf * CFrame.new(x, y, 0),
			style.material, style.color, style.attrs)
	end
	if sideW > 0.01 then
		seg(-(halfOpen + sideW/2), height/2, sideW, height)
		seg( (halfOpen + sideW/2), height/2, sideW, height)
	end
	if openY > 0.01 then seg(0, openY/2, openW, openY) end
	local topY = openY + openH
	if topY < height - 0.01 then
		local topH = height - topY
		seg(0, topY + topH/2, openW, topH)
	end
	if not isDoor and openY > 0.01 and openH > 0.01 then
		box(map, name .. "_Glass",
			Vector3.new(openW, openH, 0.1),
			cf * CFrame.new(0, openY + openH/2, 0),
			glassStyle.material, glassStyle.color, glassStyle.attrs)
	end
end




local function buildFloor(map: Folder, k: number)
	local isPodium = k <= PODIUM_FLOORS
	local fW = isPodium and PODIUM_W or TOWER_W
	local fD = isPodium and PODIUM_D or TOWER_D
	local fHW, fHD = fW / 2, fD / 2
	local baseY = BASE_Y + (k - 1) * FLOOR_H
	local midY  = baseY + FLOOR_H / 2
	local topY  = baseY + FLOOR_H

	local px = fHW - PILLAR_HALF
	local pz = fHD - PILLAR_HALF
	local pillars = {
		{-px, -pz}, {0, -pz}, {px, -pz},
		{-px,  0 },           {px,  0 },
		{-px,  pz}, {0,  pz}, {px,  pz},
	}
	local pTag = isPodium and "P" or "T"
	for i, pp in ipairs(pillars) do
		box(map, ("Pillar_%s%d_%d"):format(pTag, k, i),
			Vector3.new(PILLAR_SIZE, FLOOR_H, PILLAR_SIZE),
			CFrame.new(pp[1], midY, pp[2]),
			Enum.Material.Concrete, Color3.fromRGB(155,155,150),
			ATTRS.ConcretePillar)
	end

	box(map, ("Beam_NS_%d"):format(k),  Vector3.new(fW - PILLAR_SIZE, 0.6, 0.6),
		CFrame.new(0, topY - 0.3, -pz), Enum.Material.Metal, Color3.fromRGB(70,70,75), ATTRS.SteelBeam)
	box(map, ("Beam_NS2_%d"):format(k), Vector3.new(fW - PILLAR_SIZE, 0.6, 0.6),
		CFrame.new(0, topY - 0.3,  pz), Enum.Material.Metal, Color3.fromRGB(70,70,75), ATTRS.SteelBeam)
	box(map, ("Beam_EW_%d"):format(k),  Vector3.new(0.6, 0.6, fD - PILLAR_SIZE),
		CFrame.new( px, topY - 0.3, 0), Enum.Material.Metal, Color3.fromRGB(70,70,75), ATTRS.SteelBeam)
	box(map, ("Beam_EW2_%d"):format(k), Vector3.new(0.6, 0.6, fD - PILLAR_SIZE),
		CFrame.new(-px, topY - 0.3, 0), Enum.Material.Metal, Color3.fromRGB(70,70,75), ATTRS.SteelBeam)

	local slabState = FLOOR_SLAB[k] or 0
	local slabY     = topY + SLAB_THICK / 2
	if slabState == 2 then
		box(map, ("Slab_%d"):format(k), Vector3.new(fW, SLAB_THICK, fD),
			CFrame.new(0, slabY, 0), Enum.Material.Concrete, Color3.fromRGB(150,150,145), ATTRS.ConcreteSlab)
	elseif slabState == 1 then
		local hw, hd = fW / 2, fD / 2
		box(map, ("Slab_%d_A"):format(k), Vector3.new(hw, SLAB_THICK, fD),
			CFrame.new(-hw/2, slabY, 0), Enum.Material.Concrete, Color3.fromRGB(150,150,145), ATTRS.ConcreteSlab)
		box(map, ("Slab_%d_B"):format(k), Vector3.new(hw, SLAB_THICK, hd),
			CFrame.new( hw/2, slabY, -hd/2), Enum.Material.Concrete, Color3.fromRGB(150,150,145), ATTRS.ConcreteSlab)
	end

	local wallState = FLOOR_WALL[k] or 0
	if wallState >= 1 then
		local cfN = CFrame.new(0, baseY, -fHD)
		local cfS = CFrame.new(0, baseY,  fHD)
		local cfW = CFrame.new(-fHW, baseY, 0) * CFrame.Angles(0, math.rad(90), 0)
		if wallState == 2 then
			buildWallSide(map, ("Wall_N_%d"):format(k), cfN, fW, FLOOR_H, 3, 2.5, 1.5, CONCRETE_STYLE, GLASS_STYLE, false)
			if k == 1 then
				buildWallSide(map, ("Wall_S_%d"):format(k), cfS, fW, FLOOR_H, 4, 3.5, 0, CONCRETE_STYLE, GLASS_STYLE, true)
			else
				buildWallSide(map, ("Wall_S_%d"):format(k), cfS, fW, FLOOR_H, 3, 2.5, 1.5, CONCRETE_STYLE, GLASS_STYLE, false)
			end
			buildWallSide(map, ("Wall_W_%d"):format(k), cfW, fD, FLOOR_H, 3, 2.5, 1.5, CONCRETE_STYLE, GLASS_STYLE, false)
		else
			local hh = FLOOR_H * 0.6
			buildWallSide(map, ("Wall_N_%d"):format(k), cfN, fW, hh, 3, 2, 1, CONCRETE_STYLE, GLASS_STYLE, false)
			buildWallSide(map, ("Wall_W_%d"):format(k), cfW, fD, hh, 3, 2, 1, CONCRETE_STYLE, GLASS_STYLE, false)
		end
	end
end




local function buildExteriorStairs(map: Folder)
	local sx    = PODIUM_W / 2 - 3
	local width = 2.6
	local zNear, zFar = -8, 8
	for k = 1, TOTAL_FLOORS do
		local y0 = BASE_Y + (k - 1) * FLOOR_H
		local y1 = y0 + FLOOR_H
		local zA, zB = (k % 2 == 1) and zNear or zFar, (k % 2 == 1) and zFar or zNear
		local dz = zB - zA
		local len = math.sqrt(dz*dz + FLOOR_H*FLOOR_H)
		local zc, yc = (zA + zB) / 2, (y0 + y1) / 2
		local ang = math.atan2(FLOOR_H, dz)

		box(map, ("ExtStair_%d"):format(k),
			Vector3.new(width, 0.3, len),
			CFrame.new(sx, yc, zc) * CFrame.Angles(-ang, 0, 0),
			Enum.Material.Concrete, Color3.fromRGB(160,160,155), ATTRS.ConcreteSlab)

		box(map, ("ExtLand_%d"):format(k),
			Vector3.new(width + 1, 0.3, width + 1),
			CFrame.new(sx, y1 + 0.15, zB),
			Enum.Material.Concrete, Color3.fromRGB(160,160,155), ATTRS.ConcreteSlab)

		box(map, ("ExtRail_%d"):format(k),
			Vector3.new(0.1, 1.1, len),
			CFrame.new(sx + width/2, yc + 0.7, zc) * CFrame.Angles(-ang, 0, 0),
			Enum.Material.Metal, Color3.fromRGB(220,180,60), ATTRS.Railing)
	end
end




local function buildTowerCrane(map: Folder)
	local cx = -(PODIUM_W/2) - 8
	local cz = -(PODIUM_D/2) - 8
	local baseY = BASE_Y
	local H = 64
	local topY = baseY + H
	local mh = 0.9
	local ps = 0.2
	local Y = Color3.fromRGB(230,180,40)
	local D = Color3.fromRGB(50,50,55)
	local Mtl = Enum.Material.Metal

	
	box(map, "Crane_Pad", Vector3.new(4, 0.6, 4),
		CFrame.new(cx, baseY + 0.3, cz),
		Enum.Material.Concrete, Color3.fromRGB(120,120,115), ATTRS.Foundation)

	
	for _, sx in ipairs({-1, 1}) do
		for _, sz in ipairs({-1, 1}) do
			box(map, ("Crane_Post_%d%d"):format(sx, sz),
				Vector3.new(ps, H, ps),
				CFrame.new(cx + sx*mh, baseY + H/2, cz + sz*mh),
				Mtl, Y, ATTRS.Crane)
		end
	end

	
	local nStep = math.floor(H / 4)
	for i = 1, nStep do
		local by = baseY + i * 4
		box(map, ("Crane_HX_%d"):format(i),
			Vector3.new(2*mh + ps, ps, ps),
			CFrame.new(cx, by, cz - mh), Mtl, Y, ATTRS.Crane)
		box(map, ("Crane_HX2_%d"):format(i),
			Vector3.new(2*mh + ps, ps, ps),
			CFrame.new(cx, by, cz + mh), Mtl, Y, ATTRS.Crane)
		box(map, ("Crane_HZ_%d"):format(i),
			Vector3.new(ps, ps, 2*mh + ps),
			CFrame.new(cx - mh, by, cz), Mtl, Y, ATTRS.Crane)
		box(map, ("Crane_HZ2_%d"):format(i),
			Vector3.new(ps, ps, 2*mh + ps),
			CFrame.new(cx + mh, by, cz), Mtl, Y, ATTRS.Crane)
	end

	
	box(map, "Crane_TT", Vector3.new(2.4, 0.8, 2.4),
		CFrame.new(cx, topY, cz), Enum.Material.Metal, Color3.fromRGB(90,90,95), ATTRS.Crane)

	
	box(map, "Crane_Cab", Vector3.new(2, 2, 2),
		CFrame.new(cx + 1.4, topY + 1.1, cz + 1.4),
		Enum.Material.Glass, Color3.fromRGB(80,140,180), ATTRS.Glass)
	box(map, "Crane_CabRoof", Vector3.new(2.2, 0.15, 2.2),
		CFrame.new(cx + 1.4, topY + 2.15, cz + 1.4), Mtl, Y, ATTRS.Crane)

	
	local jibY    = topY + 2
	local jibLen  = 44
	local jibH    = 1.8
	box(map, "Crane_JibBottom", Vector3.new(jibLen, 0.25, 0.25),
		CFrame.new(cx + jibLen/2, jibY, cz), Mtl, Y, ATTRS.Crane)
	box(map, "Crane_JibTop",    Vector3.new(jibLen, 0.25, 0.25),
		CFrame.new(cx + jibLen/2, jibY + jibH, cz), Mtl, Y, ATTRS.Crane)

	local nJib = math.floor(jibLen / 3)
	local diagLen = math.sqrt(3*3 + jibH*jibH)
	local diagAng = math.atan2(jibH, 3)
	for i = 1, nJib do
		local jx = cx + (i - 0.5) * 3
		box(map, ("Crane_JV_%d"):format(i),
			Vector3.new(0.18, jibH, 0.18),
			CFrame.new(jx, jibY + jibH/2, cz), Mtl, Y, ATTRS.Crane)
		box(map, ("Crane_JDA_%d"):format(i),
			Vector3.new(diagLen, 0.12, 0.12),
			CFrame.new(jx, jibY + jibH/2, cz) * CFrame.Angles(0, 0,  diagAng),
			Mtl, Y, ATTRS.Crane)
		box(map, ("Crane_JDB_%d"):format(i),
			Vector3.new(diagLen, 0.12, 0.12),
			CFrame.new(jx, jibY + jibH/2, cz) * CFrame.Angles(0, 0, -diagAng),
			Mtl, Y, ATTRS.Crane)
	end

	
	local cjibLen = 14
	box(map, "Crane_CJibBottom", Vector3.new(cjibLen, 0.25, 0.25),
		CFrame.new(cx - cjibLen/2, jibY, cz), Mtl, Y, ATTRS.Crane)
	box(map, "Crane_CJibTop",    Vector3.new(cjibLen, 0.25, 0.25),
		CFrame.new(cx - cjibLen/2, jibY + jibH, cz), Mtl, Y, ATTRS.Crane)
	for i = 1, 3 do
		box(map, ("Crane_CW_%d"):format(i),
			Vector3.new(2.2, 1.6, 2.2),
			CFrame.new(cx - cjibLen + (i-1)*2.6, jibY - 0.8, cz),
			Enum.Material.Concrete, D, ATTRS.Crane)
	end

	
	box(map, "Crane_Apex", Vector3.new(0.4, 4, 0.4),
		CFrame.new(cx, jibY + 2.8, cz), Mtl, Y, ATTRS.Crane)
	local tieLenJ = math.sqrt(jibLen*jibLen + 4)
	local tieLenC = math.sqrt(cjibLen*cjibLen + 4)
	box(map, "Crane_TieJ", Vector3.new(tieLenJ, 0.1, 0.1),
		CFrame.new(cx + jibLen/2, jibY + 2.5, cz) * CFrame.Angles(0, 0,  math.atan2(4, jibLen)),
		Enum.Material.Metal, Color3.fromRGB(180,180,190), ATTRS.Crane)
	box(map, "Crane_TieC", Vector3.new(tieLenC, 0.1, 0.1),
		CFrame.new(cx - cjibLen/2, jibY + 2.5, cz) * CFrame.Angles(0, 0, -math.atan2(4, cjibLen)),
		Enum.Material.Metal, Color3.fromRGB(180,180,190), ATTRS.Crane)

	
	local trolleyX = cx + 26
	box(map, "Crane_Trolley", Vector3.new(0.9, 0.5, 0.9),
		CFrame.new(trolleyX, jibY - 0.4, cz), Mtl, Y, ATTRS.Crane)
	local dropLen = 22
	box(map, "Crane_Cable", Vector3.new(0.08, dropLen, 0.08),
		CFrame.new(trolleyX, jibY - dropLen/2, cz),
		Enum.Material.Metal, Color3.fromRGB(30,30,35), ATTRS.Crane)
	box(map, "Crane_HookBlock", Vector3.new(0.7, 0.9, 0.7),
		CFrame.new(trolleyX, jibY - dropLen, cz), Mtl, Y, ATTRS.Crane)
	box(map, "Crane_Load", Vector3.new(4, 0.35, 4),
		CFrame.new(trolleyX, jibY - dropLen - 0.6, cz),
		Enum.Material.Concrete, Color3.fromRGB(160,160,155), ATTRS.ConcreteSlab)

	
	box(map, "Crane_Beacon", Vector3.new(0.35, 0.35, 0.35),
		CFrame.new(cx, jibY + 5, cz), Enum.Material.Neon, Color3.fromRGB(255,40,40), ATTRS.Crane)
end




local function buildScaffold(map: Folder)
	local x  = PODIUM_W/2 + 3
	local z0, z1 = -(PODIUM_D/2) + 4, (PODIUM_D/2) - 4
	local y0 = BASE_Y
	local y1 = BASE_Y + 6 * FLOOR_H
	local nV = 4
	local Y = Color3.fromRGB(220,180,60)
	for i = 0, nV do
		local z = z0 + (z1 - z0) * i / nV
		box(map, ("Scaf_VP_%d"):format(i),
			Vector3.new(0.15, y1 - y0, 0.15),
			CFrame.new(x, (y0 + y1)/2, z),
			Enum.Material.Metal, Y, ATTRS.Scaffold)
	end
	local step = 3
	local levels = math.floor((y1 - y0) / step)
	for k = 0, levels do
		local by = y0 + k * step
		box(map, ("Scaf_HR_%d"):format(k),
			Vector3.new(0.1, 0.1, z1 - z0),
			CFrame.new(x, by, (z0 + z1)/2),
			Enum.Material.Metal, Y, ATTRS.Scaffold)
		if k > 0 and k % 2 == 0 then
			box(map, ("Scaf_Plat_%d"):format(k),
				Vector3.new(1.6, 0.08, z1 - z0),
				CFrame.new(x - 0.8, by, (z0 + z1)/2),
				Enum.Material.WoodPlanks, Color3.fromRGB(180,140,80), ATTRS.Scaffold)
		end
	end
end




local function buildMaterials(map: Folder)
	local dx, dz = PODIUM_W/2 + 8, -PODIUM_D/2 + 6

	
	for row = 0, 2 do
		for col = 0, 3 do
			box(map, ("Pipe_%d_%d"):format(row, col),
				Vector3.new(1.2, 1.2, 3),
				CFrame.new(dx + 6 + col * 1.3, BASE_Y + 0.6 + row * 1.2, dz + 4),
				Enum.Material.Concrete, Color3.fromRGB(140,140,140), ATTRS.PipeStack)
		end
	end

	
	for i = 1, 4 do
		for j = 1, 5 do
			box(map, ("Rebar_%d_%d"):format(i, j),
				Vector3.new(0.1, 0.1, 6),
				CFrame.new(dx + 2 + i*0.25, BASE_Y + 0.2 + j*0.12, dz - 8),
				Enum.Material.Metal, Color3.fromRGB(180,120,80), ATTRS.Rebar)
		end
	end

	
	for i = 1, 3 do
		box(map, ("Form_%d"):format(i),
			Vector3.new(3, 0.15, 2),
			CFrame.new(dx - 6, BASE_Y + 1.4, dz + 2) * CFrame.Angles(0, 0, math.rad(75)),
			Enum.Material.WoodPlanks, Color3.fromRGB(180,140,80), ATTRS.Formwork)
	end

	
	for row = 0, 1 do
		for col = 0, 2 do
			box(map, ("Brick_%d_%d"):format(row, col),
				Vector3.new(1.5, 0.4, 1.2),
				CFrame.new(dx - 2 + col * 1.6, BASE_Y + 0.3 + row * 0.45, dz - 14),
				Enum.Material.Brick, Color3.fromRGB(150,80,60), ATTRS.MaterialPile)
		end
	end

	
	for i = 1, 4 do
		box(map, ("Drum_%d"):format(i),
			Vector3.new(0.7, 1.1, 0.7),
			CFrame.new(-(PODIUM_W/2) - 4 + (i-1)*0.9, BASE_Y + 0.55, PODIUM_D/2 + 2),
			Enum.Material.Metal, Color3.fromRGB(60,110,60), ATTRS.MaterialPile)
	end
end




local function buildMixingStation(map: Folder)
	local mx = -(PODIUM_W/2) - 12
	local mz = PODIUM_D/2 - 8

	for i = 1, 2 do
		local sx = mx + (i - 1.5) * 6
		box(map, ("Silo_Cyl_%d"):format(i),
			Vector3.new(3, 14, 3),
			CFrame.new(sx, BASE_Y + 7, mz),
			Enum.Material.Metal, Color3.fromRGB(180,180,190), ATTRS.Silo)
		box(map, ("Silo_Cone_%d"):format(i),
			Vector3.new(3, 2, 3),
			CFrame.new(sx, BASE_Y + 15, mz),
			Enum.Material.Metal, Color3.fromRGB(180,180,190), ATTRS.Silo)
		box(map, ("Silo_Leg_%dA"):format(i),
			Vector3.new(0.2, 3, 0.2),
			CFrame.new(sx - 1, BASE_Y + 1.5, mz - 1),
			Enum.Material.Metal, Color3.fromRGB(90,90,95), ATTRS.MaterialPile)
		box(map, ("Silo_Leg_%dB"):format(i),
			Vector3.new(0.2, 3, 0.2),
			CFrame.new(sx + 1, BASE_Y + 1.5, mz + 1),
			Enum.Material.Metal, Color3.fromRGB(90,90,95), ATTRS.MaterialPile)
	end

	
	box(map, "PumpHopper", Vector3.new(2, 1.5, 2),
		CFrame.new(mx + 5, BASE_Y + 0.9, mz - 5),
		Enum.Material.Metal, Color3.fromRGB(230,110,50), ATTRS.MaterialPile)
	
	local ang = math.rad(-55)
	box(map, "PumpArm", Vector3.new(0.4, 0.4, 40),
		CFrame.new(mx + 22, BASE_Y + 22, mz - 5) * CFrame.Angles(ang, 0, 0),
		Enum.Material.Metal, Color3.fromRGB(230,110,50), ATTRS.SteelBeam)
	
	box(map, "PumpEnd", Vector3.new(0.4, 2, 0.4),
		CFrame.new(mx + 22, BASE_Y + 38, mz - 18),
		Enum.Material.Metal, Color3.fromRGB(230,110,50), ATTRS.SteelBeam)
end




local function buildContainers(map: Folder)
	
	local cx = PODIUM_W/2 + 14
	local cz = PODIUM_D/2 - 6
	box(map, "Office_Lower", Vector3.new(6, 2.6, 12),
		CFrame.new(cx, BASE_Y + 1.3, cz),
		Enum.Material.CorrodedMetal, Color3.fromRGB(70,120,160), ATTRS.Container)
	box(map, "Office_Upper", Vector3.new(6, 2.6, 12),
		CFrame.new(cx, BASE_Y + 3.9, cz),
		Enum.Material.CorrodedMetal, Color3.fromRGB(190,90,60), ATTRS.Container)
	
	for i = 1, 3 do
		box(map, ("Office_Win_%d"):format(i), Vector3.new(0.1, 1, 1.8),
			CFrame.new(cx - 3.05, BASE_Y + 1.4, cz - 4 + i * 3),
			Enum.Material.Glass, Color3.fromRGB(150,200,230), ATTRS.Glass)
	end

	
	box(map, "Storage", Vector3.new(6, 2.6, 12),
		CFrame.new(cx + 8, BASE_Y + 1.3, cz + 2),
		Enum.Material.CorrodedMetal, Color3.fromRGB(160,140,90), ATTRS.Container)
end




local function buildFence(map: Folder)
	local FenceMat   = Enum.Material.Metal
	local FenceColor = Color3.fromRGB(120,120,130)
	local function fenceSeg(name: string, x0, z0, x1, z1)
		local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
		local len = math.sqrt((x1-x0)^2 + (z1-z0)^2)
		local ang = math.atan2(z1 - z0, x1 - x0)
		box(map, name, Vector3.new(len, 2.2, 0.1),
			CFrame.new(cx, BASE_Y + 1.1, cz) * CFrame.Angles(0, -ang, 0),
			FenceMat, FenceColor, ATTRS.Railing)
	end
	
	fenceSeg("Fence_S1", SITE_X0, SITE_Z1, -GATE_W/2, SITE_Z1)
	fenceSeg("Fence_S2", GATE_W/2, SITE_Z1, SITE_X1, SITE_Z1)
	
	fenceSeg("Fence_N",  SITE_X0, SITE_Z0, SITE_X1, SITE_Z0)
	fenceSeg("Fence_E",  SITE_X1, SITE_Z0, SITE_X1, SITE_Z1)
	fenceSeg("Fence_W",  SITE_X0, SITE_Z0, SITE_X0, SITE_Z1)
	
	box(map, "GatePostL", Vector3.new(0.4, 3, 0.4),
		CFrame.new(-GATE_W/2, BASE_Y + 1.5, SITE_Z1),
		FenceMat, Color3.fromRGB(200,180,40), ATTRS.Railing)
	box(map, "GatePostR", Vector3.new(0.4, 3, 0.4),
		CFrame.new( GATE_W/2, BASE_Y + 1.5, SITE_Z1),
		FenceMat, Color3.fromRGB(200,180,40), ATTRS.Railing)
end




local function buildSiteLights(map: Folder)
	local positions = {
		{ SITE_X0 + 4, SITE_Z0 + 4 },
		{ SITE_X1 - 4, SITE_Z0 + 4 },
		{ SITE_X0 + 4, SITE_Z1 - 4 },
		{ SITE_X1 - 4, SITE_Z1 - 4 },
	}
	for i, p in ipairs(positions) do
		box(map, ("LightPole_%d"):format(i), Vector3.new(0.3, 12, 0.3),
			CFrame.new(p[1], BASE_Y + 6, p[2]),
			Enum.Material.Metal, Color3.fromRGB(80,80,90), ATTRS.SiteLight)
		box(map, ("LightLamp_%d"):format(i), Vector3.new(1.6, 0.6, 1.6),
			CFrame.new(p[1], BASE_Y + 12.3, p[2]),
			Enum.Material.Neon, Color3.fromRGB(255,240,180), ATTRS.SiteLight)
	end
end




local function buildSigns(map: Folder)
	local signX = -GATE_W/2 - 2
	local signZ = SITE_Z1 - 1
	
	box(map, "SignPost", Vector3.new(0.3, 4, 0.3),
		CFrame.new(signX, BASE_Y + 2, signZ),
		Enum.Material.Metal, Color3.fromRGB(90,90,95), ATTRS.Sign)
	
	box(map, "SignBoard", Vector3.new(3, 1.4, 0.15),
		CFrame.new(signX, BASE_Y + 3.6, signZ),
		Enum.Material.Metal, Color3.fromRGB(230,190,40), ATTRS.Sign)
	box(map, "SignStripe", Vector3.new(2.8, 0.2, 0.16),
		CFrame.new(signX, BASE_Y + 3.6, signZ - 0.02),
		Enum.Material.Neon, Color3.fromRGB(40,40,40), ATTRS.Sign)
end




local function buildDetails(map: Folder)
	
	local tY = BASE_Y + 6 * FLOOR_H + SLAB_THICK + 0.05
	box(map, "Tarp_6", Vector3.new(8, 0.05, 8),
		CFrame.new(-8, tY, 4),
		Enum.Material.Fabric, Color3.fromRGB(70,110,150), ATTRS.Tarp)
	
	box(map, "TarpHang", Vector3.new(8, 5, 0.05),
		CFrame.new(0, BASE_Y + 8 * FLOOR_H + 2, -TOWER_D/2 - 0.1),
		Enum.Material.Fabric, Color3.fromRGB(70,110,150), ATTRS.Tarp)

	
	for i = 1, 4 do
		local y = BASE_Y + (i - 1) * FLOOR_H + 1.5
		box(map, ("Ladder_%d"):format(i), Vector3.new(0.6, 3, 0.15),
			CFrame.new(-TOWER_W/2 + 0.3, y, -TOWER_D/2 + 0.1),
			Enum.Material.Metal, Color3.fromRGB(200,180,60), ATTRS.Railing)
	end

	
	box(map, "Generator", Vector3.new(2, 1.2, 3),
		CFrame.new(PODIUM_W/2 + 22, BASE_Y + 0.6, -PODIUM_D/2 + 4),
		Enum.Material.Metal, Color3.fromRGB(210,120,40), ATTRS.Container)

	
	box(map, "CableCoil", Vector3.new(2, 0.6, 2),
		CFrame.new(PODIUM_W/2 + 5, BASE_Y + 0.3, -(PODIUM_D/2) - 5),
		Enum.Material.Metal, Color3.fromRGB(40,40,45), ATTRS.MaterialPile)
end




local function buildTopRebar(map: Folder)
	local topY = BASE_Y + TOTAL_FLOORS * FLOOR_H
	local hw = TOWER_W / 2 - PILLAR_HALF
	local hd = TOWER_D / 2 - PILLAR_HALF
	local corners = {
		{ hw, -hd }, { hw, hd }, { -hw, -hd }, { -hw, hd },
		{ 0, -hd }, { 0, hd }, { hw, 0 }, { -hw, 0 },
	}
	for i, c in ipairs(corners) do
		box(map, ("TopRebar_%d"):format(i),
			Vector3.new(0.15, 2.4, 0.15),
			CFrame.new(c[1], topY + 1.2, c[2]),
			Enum.Material.Metal, Color3.fromRGB(180,120,80), ATTRS.Rebar)
	end
	for i = 1, 6 do
		local a = (i - 1) * math.pi / 3
		box(map, ("TopCluster_%d"):format(i),
			Vector3.new(0.12, 3.2, 0.12),
			CFrame.new(math.cos(a) * 2, topY + 1.6, math.sin(a) * 2),
			Enum.Material.Metal, Color3.fromRGB(180,120,80), ATTRS.Rebar)
	end
end




function TestMapBuilder.Build(): Instance
	local map = getMapFolder()
	for _, c in ipairs(map:GetChildren()) do c:Destroy() end

	
	local spawn = Instance.new("SpawnLocation")
	spawn.Name       = "Spawn"
	spawn.Size       = Vector3.new(6, 0.5, 6)
	spawn.CFrame     = CFrame.new(0, BASE_Y + 0.25, 24)
	spawn.Anchored   = true
	spawn.Parent     = map

	
	box(map, "Foundation",
		Vector3.new(PODIUM_W + 14, BASE_H, PODIUM_D + 14),
		CFrame.new(0, BASE_Y - BASE_H/2, 0),
		Enum.Material.Concrete, Color3.fromRGB(85,85,90), ATTRS.Foundation)

	
	for k = 1, TOTAL_FLOORS do
		buildFloor(map, k)
	end

	
	buildTowerCrane(map)

	
	buildExteriorStairs(map)

	
	buildScaffold(map)

	
	buildTopRebar(map)

	
	local podHW, podHD = PODIUM_W/2, PODIUM_D/2
	local towerHW, towerHD = TOWER_W/2, TOWER_D/2
	local roofY = BASE_Y + PODIUM_FLOORS * FLOOR_H + SLAB_THICK
	
	box(map, "PodiumRailN", Vector3.new(PODIUM_W, 1, 0.15),
		CFrame.new(0, roofY + 0.5, -podHD + 0.2),
		Enum.Material.Metal, Color3.fromRGB(200,180,60), ATTRS.Railing)
	
	box(map, "PodiumRailS", Vector3.new(PODIUM_W, 1, 0.15),
		CFrame.new(0, roofY + 0.5, podHD - 0.2),
		Enum.Material.Metal, Color3.fromRGB(200,180,60), ATTRS.Railing)
	
	box(map, "PodiumRailW", Vector3.new(0.15, 1, PODIUM_D),
		CFrame.new(-podHW + 0.2, roofY + 0.5, 0),
		Enum.Material.Metal, Color3.fromRGB(200,180,60), ATTRS.Railing)
	
	box(map, "PodiumRailE1", Vector3.new(0.15, 1, (podHD - towerHD) - 2),
		CFrame.new(podHW - 0.2, roofY + 0.5, -podHD + ((podHD - towerHD) - 2)/2),
		Enum.Material.Metal, Color3.fromRGB(200,180,60), ATTRS.Railing)

	
	buildMixingStation(map)
	buildContainers(map)
	buildMaterials(map)

	
	buildFence(map)
	buildSiteLights(map)
	buildSigns(map)

	
	buildDetails(map)

	
	local n = 0
	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("BasePart") then n += 1 end
	end
	print(("[TestMapBuilder] Built HIGH-RISE CONSTRUCTION SITE — %d parts, %d floors (%.0f×%.0f, top Y≈%.0f)")
		:format(n, TOTAL_FLOORS, TOWER_W, TOWER_D, BASE_Y + TOTAL_FLOORS * FLOOR_H))

	if _G.DestructionRebuild then
		print("[TestMapBuilder] Triggering graph rebuild...")
		task.defer(_G.DestructionRebuild)
	else
		print("[TestMapBuilder] Bootstrap chưa chạy. Play → Bootstrap sẽ tự load map này.")
	end

	return map
end

return TestMapBuilder
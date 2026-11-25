--!strict
--!native

local Debris = game:GetService("Debris")

local Draw: any = {}

local ctx: any = nil
local folder: Folder? = nil
local live = 0

function Draw.Init(c: any)
	ctx = c
end

local function getFolder(): Folder
	if folder and folder.Parent then return folder end
	local f = Instance.new("Folder")
	f.Name = "DebugDraw"
	f.Parent = workspace
	folder = f
	return f
end

local function mk(size: Vector3, cf: CFrame, color: Color3, partType: Enum.PartType?, ttl: number, transparency: number?): BasePart?
	if live >= ctx.Config.Debug.MaxDrawParts then return nil end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency or 0.65
	if partType then p.Shape = partType end
	p.Size = size
	p.CFrame = cf
	p.Parent = getFolder()
	live += 1
	p.Destroying:Connect(function() live -= 1 end)
	Debris:AddItem(p, ttl)
	return p
end

local function axisCF(center: Vector3, look: Vector3): CFrame
	local ref = if math.abs(look.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local y = (ref - look * ref:Dot(look)).Unit
	return CFrame.fromMatrix(center, look, y)
end

function Draw.Clear()
	local f = folder
	if f then f:ClearAllChildren() end
	live = 0
end

function Draw.Point(pos: Vector3, color: Color3?, size: number?, ttl: number?)
	local s = size or 0.8
	mk(Vector3.new(s, s, s), CFrame.new(pos), color or Color3.new(1, 1, 1), Enum.PartType.Ball, ttl or ctx.Config.Debug.DrawTTL, 0.1)
end

function Draw.Line(a: Vector3, b: Vector3, color: Color3?, ttl: number?)
	local len = (b - a).Magnitude
	if len < 1e-3 then return end
	mk(Vector3.new(len, 0.2, 0.2), axisCF((a + b) * 0.5, (b - a) / len), color or Color3.new(1, 1, 0),
		Enum.PartType.Cylinder, ttl or ctx.Config.Debug.DrawTTL, 0.2)
end

function Draw.Shape(shape: any, color: Color3?, ttl: number?)
	local col = color or Color3.fromRGB(255, 140, 40)
	local life = ttl or ctx.Config.Debug.DrawTTL
	local cf: CFrame = shape.CFrame
	local pos, look = cf.Position, cf.LookVector
	local kind: string = shape.Type

	if kind == "Sphere" then
		local r = shape.Radius or 1
		mk(Vector3.new(r * 2, r * 2, r * 2), CFrame.new(pos), col, Enum.PartType.Ball, life)

	elseif kind == "Box" then
		mk(shape.Size or Vector3.new(2, 2, 2), cf, col, nil, life)

	elseif kind == "Capsule" or kind == "Cylinder" or kind == "Line" then
		local len = shape.Length or 4
		local r = shape.Radius or (if kind == "Line" then 0.25 else 1)
		local a = if shape.Centered then pos - look * (len * 0.5) else pos
		local b = a + look * len
		mk(Vector3.new(len, r * 2, r * 2), axisCF((a + b) * 0.5, look), col, Enum.PartType.Cylinder, life)
		if kind == "Capsule" then
			mk(Vector3.new(r * 2, r * 2, r * 2), CFrame.new(a), col, Enum.PartType.Ball, life)
			mk(Vector3.new(r * 2, r * 2, r * 2), CFrame.new(b), col, Enum.PartType.Ball, life)
		end

	elseif kind == "Cone" then
		local len = shape.Length or 8
		local tan = math.tan(math.rad(math.clamp(shape.HalfAngle or 30, 1, 89)))
		for _, f in ipairs({ 0.25, 0.5, 0.75, 1 }) do
			local s = len * f
			local rr = s * tan
			mk(Vector3.new(0.15, rr * 2, rr * 2), axisCF(pos + look * s, look), col, Enum.PartType.Cylinder, life, 0.75)
		end
		Draw.Line(pos, pos + look * len, col, life)
	end

	Draw.Point(pos, Color3.new(1, 1, 1), 0.6, life)
end

function Draw.Hits(graph: any, hits: { any }, ttl: number?)
	local maxF = 1e-6
	for _, h in ipairs(hits) do
		if h.force > maxF then maxF = h.force end
	end
	local life = ttl or ctx.Config.Debug.DrawTTL
	for _, h in ipairs(hits) do
		local node = graph.Nodes[h.idx]
		if node then
			local t = math.clamp(h.force / maxF, 0, 1)
			mk(node.Size * 0.92, CFrame.new(node.Position), Color3.fromHSV((1 - t) * 0.33, 1, 1), nil, life, 0.5)
		end
	end
end

return Draw

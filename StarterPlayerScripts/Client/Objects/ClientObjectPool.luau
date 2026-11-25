--!strict
--!native

local mathmin = math.min

local MAX_POOL_SIZE = 2000
local PREWARM_COUNT = 1500
local DEFAULT_MATERIAL = Enum.Material.Plastic
local DEFAULT_COLOR    = Color3.new(1, 1, 1)

local ClientObjectPool = {}

local pool: { BasePart } = {}

local function createNewPart(): BasePart
	local p = Instance.new("Part")
	p.Name = "Debris"
	p.Anchored = true
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

local function resetPart(part: BasePart)
	part.Parent = nil
	part.Anchored = true
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.Transparency = 0
	part.Size = Vector3.one
	part.CFrame = CFrame.new()
	part.Color = DEFAULT_COLOR
	part.Material = DEFAULT_MATERIAL
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero

	local children = part:GetChildren()
	if #children > 0 then
		part:ClearAllChildren()
	end
end

function ClientObjectPool.Prewarm(count: number?)
	local target = count or PREWARM_COUNT
	local current = #pool
	local toAdd = mathmin(target, MAX_POOL_SIZE - current)
	if toAdd <= 0 then return end
	for i = 1, toAdd do
		pool[current + i] = createNewPart()
	end
end

function ClientObjectPool.Acquire(): BasePart
	local n = #pool
	local part: BasePart
	if n > 0 then
		part = pool[n]
		pool[n] = nil
	else
		part = createNewPart()
	end
	resetPart(part)
	return part
end

function ClientObjectPool.Release(part: BasePart)
	if not part then return end
	part.Parent = nil
	local n = #pool
	if n < MAX_POOL_SIZE then
		pool[n + 1] = part
	else
		part:Destroy()
	end
end

function ClientObjectPool.BatchAcquire(count: number): { BasePart }
	local result = table.create(count)

	local n = #pool
	local fromPool = mathmin(n, count)
	for i = 1, fromPool do
		result[i] = pool[n]
		pool[n] = nil
		n = n - 1
	end
	for i = fromPool + 1, count do
		result[i] = createNewPart()
	end
	for i = 1, count do
		resetPart(result[i])
	end

	return result
end

function ClientObjectPool.BatchRelease(parts: { BasePart })
	if not parts then return end
	local n = #pool
	for i = 1, #parts do
		local p = parts[i]
		if p then
			p.Parent = nil
			if n < MAX_POOL_SIZE then
				n = n + 1
				pool[n] = p
			else
				p:Destroy()
			end
		end
	end
end

function ClientObjectPool.GetPoolSize(): number
	return #pool
end

return ClientObjectPool
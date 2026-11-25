--!strict
--!native
-- StarterPlayerScripts/Client/MapLoader/ClientMapLoader.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapSerializer     = require(ReplicatedStorage.Shared.Map.MapSerializer)

local ClientObjectPool = require(script.Parent.Parent.Objects.ClientObjectPool)

local typeOf = typeof
local ins    = table.insert

local ClientMapLoader = {}

ClientObjectPool.Prewarm(300)

-- SAFE MATERIAL CONVERSION
--
local function toMaterial(v: any): Enum.Material
	if typeOf(v) == "EnumItem" then
		if v.EnumType == Enum.Material then
			return v
		end
		return Enum.Material.Plastic
	end
	if typeOf(v) == "number" then
		local ok, mat = pcall(function()
			return Enum.Material:FromValue(v)
		end)
		if ok and mat then
			return mat :: Enum.Material
		end
		return Enum.Material.Plastic
	end
	return Enum.Material.Plastic
end

-- BuildMap
function ClientMapLoader.BuildMap(
	buffer: buffer,
	replication: any?
): ({ BasePart }, { [number]: BasePart })
	local partsData = MapSerializer.DeserializeMap(buffer)
	local staticParts: { BasePart } = {}
	local partIndexMap: { [number]: BasePart } = {}

	local cam = workspace.Camera
	if not cam then return staticParts, partIndexMap end

	local oldMap = cam:FindFirstChild("Map")
	if oldMap then
		if replication and replication.DynamicParts then
			for _, p in ipairs(oldMap:GetDescendants()) do
				if p:IsA("BasePart") then
					local objId = p:GetAttribute("ObjectId")
					if objId then
						replication.DynamicParts[objId] = nil
						if replication.Targets then
							replication.Targets[objId] = nil
						end
					end
				end
			end
		end
		oldMap:Destroy()
	end

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = cam

	for partIndex, pData in pairs(partsData) do
		local visPart = Instance.new("Part")
		visPart.Name       = pData.Name
		visPart.Anchored   = true
		visPart.CanCollide = true
		visPart.CanQuery   = true
		visPart.CanTouch   = true
		visPart.Size       = pData.Size
		visPart.CFrame     = pData.CFrame
		visPart.Material   = toMaterial(pData.Material)
		visPart.Color      = pData.Color

		visPart:SetAttribute("PartIndex", partIndex)
		visPart:SetAttribute("IsAnchor", pData.IsAnchor == true)
		visPart:SetAttribute("IsFalling", false)

		visPart.Parent = mapFolder
		ins(staticParts, visPart)
		partIndexMap[partIndex] = visPart
	end

	return staticParts, partIndexMap
end

-- BuildDebris
function ClientMapLoader.BuildDebris(buffer: buffer, replication: any)
	local debrisData = MapSerializer.DeserializeDebris(buffer)
	local cam = workspace.Camera
	if not cam then return end

	local n = #debrisData
	if n == 0 then return end

	local parts = ClientObjectPool.BatchAcquire(n)

	for i, d in ipairs(debrisData) do
		local visPart = parts[i]
		visPart.Name       = "Debris_" .. d.Id
		visPart.Size       = d.Size
		visPart.CFrame     = d.CFrame
		visPart.Material   = toMaterial(d.Material)
		visPart.Color      = d.Color

		visPart.Anchored   = true
		visPart.Massless   = true
		visPart.CanCollide = true
		visPart.CanQuery   = false
		visPart.CanTouch   = false

		visPart:SetAttribute("ObjectId", d.Id)

		replication:RegisterPart(d.Id, visPart)
	end

	for i = 1, n do
		parts[i].Parent = cam
	end
end

return ClientMapLoader

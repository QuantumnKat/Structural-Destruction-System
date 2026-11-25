--!strict
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local MapSerializer     = require(ReplicatedStorage.Shared.Map.MapSerializer)
local SnapshotCodec     = require(ReplicatedStorage.Shared.Destruction.SnapshotCodec)
local Quantize          = require(ReplicatedStorage.Shared.World.Spatial.Quantize)
local ClientSpawnSync   = require(script.Parent.ClientSpawnSync) 

local typeOf = typeof

local ClientDestructionHandler = {}
local PartIndexMap: { [number]: BasePart } = {}
local FallingOffset: number? = nil
local connections: { RBXScriptConnection } = {}

function ClientDestructionHandler.Stop()
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
end

local function toMaterial(v: any): Enum.Material
	if typeOf(v) == "EnumItem" and v.EnumType == Enum.Material then return v end
	if typeOf(v) == "number" then
		local ok, mat = pcall(function() return Enum.Material:FromValue(v) end)
		if ok and mat then return mat :: Enum.Material end
	end
	return Enum.Material.Plastic
end


local function applySnapshot(buf: buffer, clientRep: any)
	local maxIdx, _seq, state, poses, poseCount = SnapshotCodec.Unpack(buf)
	if not maxIdx or not state then return end

	for idx = 1, maxIdx do
		if SnapshotCodec.GetState(state, idx) == 2 then
			local part = PartIndexMap[idx]
			if part then
				clientRep:ForgetPart(part)
				if part.Parent then part:Destroy() end
				PartIndexMap[idx] = nil
			end
		end
	end

	if poses then
		for i = 0, poseCount - 1 do
			local o = i * 16
			local part = PartIndexMap[buffer.readu32(poses, o)]
			if part and part.Parent then
				part.CFrame = Quantize.Int16ToCFrame(
					buffer.readi16(poses, o + 4), buffer.readi16(poses, o + 6), buffer.readi16(poses, o + 8),
					buffer.readi16(poses, o + 10), buffer.readi16(poses, o + 12), buffer.readi16(poses, o + 14)
				)
			end
		end
	end
end



function ClientDestructionHandler.Setup(
	replicationEvent: RemoteEvent,
	clientRep: any,
	indexMap: { [number]: BasePart },
	fallingIdOffset: number?
)
	ClientDestructionHandler.Stop()
	PartIndexMap = indexMap
	fallingIdOffset = fallingIdOffset or 1_000_000
	FallingOffset = fallingIdOffset
	ClientSpawnSync.Setup(clientRep)

	if fallingIdOffset and clientRep.SetResolver then
		clientRep:SetResolver(function(partId: number): BasePart?
			if partId < fallingIdOffset then return nil end
			local part = PartIndexMap[partId - fallingIdOffset]
			if part and part.Parent then
				part:SetAttribute("IsFalling", true)
				part.Massless   = true
				part.CanCollide = true
				part.CanTouch   = false
				return part
			end
			return nil
		end)
	end

	table.insert(connections, replicationEvent.OnClientEvent:Connect(function(action: string, data: any)
		if action == "DESTROY_PART" then
			local part = PartIndexMap[data]
			if not part and FallingOffset then
				
				part = clientRep.DynamicParts[data + FallingOffset]
			end
			if part then
				
				clientRep:ForgetPart(part)
				if part.Parent then
					part:Destroy()
				end
			end
			PartIndexMap[data] = nil
			
			

		elseif action == "COLLAPSE_PARTS" then
			for _, idx in ipairs(data) do
				local part = PartIndexMap[idx]
				if part and part.Parent then
					part:SetAttribute("IsFalling", true)
					part.Massless   = true
					part.CanCollide = true
					part.CanTouch   = false
					
					
					part:SetAttribute("ObjectId", idx + (FallingOffset :: number))
				clientRep:WatchPart(part)
				end
			end

		elseif action == "KNOCKBACK" then
			
			if typeOf(data) == "Vector3" then
				local char = Players.LocalPlayer and Players.LocalPlayer.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					root:ApplyImpulse(data * root.AssemblyMass)
				end
			end

		elseif action == "DEBUG_PROBE" then
			
			if typeOf(data) == "table" and typeOf(data.ids) == "table" then
				local found: { boolean } = {}
				local pos: { Vector3 } = {}
				for i, id in ipairs(data.ids) do
					local part = clientRep.DynamicParts[id]
					if part and part.Parent then
						found[i] = true
						pos[i] = part.Position
					else
						found[i] = false
						pos[i] = Vector3.zero
					end
				end
				local nDyn, nTargets = 0, 0
				for _ in pairs(clientRep.DynamicParts) do nDyn += 1 end
				for _ in pairs(clientRep.Targets) do nTargets += 1 end
				replicationEvent:FireServer("DEBUG_PROBE_REPLY", {
					token = data.token, found = found, pos = pos,
					stats = { dynamicParts = nDyn, targets = nTargets },
				})
			end

		elseif action == "SPAWN_PARTS" then
			if typeOf(data) == "buffer" then
				ClientSpawnSync.OnSpawn(data)
			end

		elseif action == "DESPAWN_PARTS" then
			if typeOf(data) == "buffer" then
				ClientSpawnSync.OnDespawn(data)
			end

		elseif action == "SNAPSHOT_STATE" then
			if typeOf(data) == "buffer" then
				applySnapshot(data, clientRep)
			end

		elseif action == "CREATE_STATIC_PARTS" then
			local cam = workspace:FindFirstChild("Camera")
			local mapFolder = cam and cam:FindFirstChild("Map")
			if not mapFolder then
				warn("[ClientDestruction] Map folder not found")
				return
			end
			local staticParts = MapSerializer.DeserializeDebris(data)
			for _, info in ipairs(staticParts) do
				local p = Instance.new("Part")
				p.Size       = info.Size
				p.CFrame     = info.CFrame
				p.Color      = info.Color
				p.Material   = toMaterial(info.Material)
				p.Anchored   = true
				p.CanCollide = true
				p.CanQuery   = true
				if info.Id then
					p:SetAttribute("PartIndex", info.Id)
					PartIndexMap[info.Id] = p
				end
				p.Parent     = mapFolder
			end
		end
	end))

	table.insert(connections, workspace.DescendantRemoving:Connect(function(desc)
		if desc:IsA("BasePart") then
			local partIdx = desc:GetAttribute("PartIndex")
			if partIdx and PartIndexMap[partIdx] == desc then
				PartIndexMap[partIdx] = nil
			end
		end
	end))

	print("[ClientDestructionHandler] Setup complete")
end

return ClientDestructionHandler
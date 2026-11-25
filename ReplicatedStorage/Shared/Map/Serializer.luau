--!strict
--!native

local MapLoaderConfig = require(script.Parent.MapLoaderConfig)
local CFG = MapLoaderConfig

local ins        = table.insert
local bcreate    = buffer.create
local writeu8    = buffer.writeu8
local writeu16   = buffer.writeu16
local writeu32   = buffer.writeu32
local writef32   = buffer.writef32
local writestr   = buffer.writestring
local readu8     = buffer.readu8
local readu16    = buffer.readu16
local readu32    = buffer.readu32
local readf32    = buffer.readf32
local readstr    = buffer.readstring

local mathround  = math.round
local mathmin    = math.min
local mathclamp  = math.clamp
local stringSub  = string.sub
local stringFmt  = string.format

local VERSION     = CFG.SERIALIZER_VERSION
local VERSION_MIN = CFG.SERIALIZER_VERSION_MIN
local MAX_STR_LEN = 255

local Serializer = {}

export type MeshData = { MeshId: string, TextureId: string, Scale: Vector3 }

export type PartData = {
	Name: string, CFrame: CFrame, Size: Vector3, Mass: number,
	CenterOfMass: Vector3?, Category: number, Material: number, Color: Color3,
	TextureId: string, MeshIndex: number,
	HP: number, Hardness: number, ForceTransmission: number, StressResistance: number,
	TensileStrength: number, BendingForce: number, CompressionStrength: number,
	Pressure: number,
	IsAnchor: boolean, IsDestructible: boolean,
	OnDisconnect: string?, BreakRadius: number?,
	ShatterAirPercent: number?, MaxDebrisPerPart: number?,
	UnweldPercentage: number?,
	IsFalling: boolean?,
	ClusterId: number?,
}

export type WeldData = {
	PartA: number, PartB: number,
	OffsetA: Vector3, OffsetB: Vector3,
	DamageSeed: number?,
}

export type BoxData = {
	GlobalId: number, Pos: Vector3, Size: Vector3, PartIndex: number,
	DamageSeed: number?,
}

export type MapPayload = {
	OriginPosition: Vector3, OriginRotation: CFrame, ModelSize: Vector3,
	VoxelSize: number,
	Meshes: { MeshData }, Parts: { PartData },
	Boxes: { BoxData }, Welds: { WeldData },
}

local ON_DISCONNECT_ENCODE: { [string]: number } = {
	["Auto"] = 0, ["Ignore"] = 1, ["Detach"] = 2, ["Break"] = 3, ["Shatter"] = 4,
}
local ON_DISCONNECT_DECODE: { string } = {
	"Auto", "Ignore", "Detach", "Break", "Shatter",
}

local function clampByte(v: number): number
	local r = mathround(v)
	if r < 0 then return 0 end
	if r > 255 then return 255 end
	return r
end

local function computeTotalSize(payload: MapPayload): number
	local total = 57

	local meshes = payload.Meshes
	if meshes then
		for i = 1, #meshes do
			local m = meshes[i]
			local ml = #(m.MeshId or "")
			if ml > MAX_STR_LEN then ml = MAX_STR_LEN end
			local tl = #(m.TextureId or "")
			if tl > MAX_STR_LEN then tl = MAX_STR_LEN end
			total = total + 1 + ml + 1 + tl + 12
		end
	end

	local parts = payload.Parts
	if parts then
		for i = 1, #parts do
			local p = parts[i]
			local nl = #(p.Name or "")
			if nl > MAX_STR_LEN then nl = MAX_STR_LEN end
			local tl = #(p.TextureId or "")
			if tl > MAX_STR_LEN then tl = MAX_STR_LEN end
			total = total + 116 + nl + tl
		end
	end

	local boxes = payload.Boxes
	if boxes then
		total = total + #boxes * 34
	end

	local welds = payload.Welds
	if welds then
		total = total + #welds * 32
	end

	return total
end

local function getSafeCOM(part: PartData): Vector3
	local com = part.CenterOfMass
	if typeof(com) == "Vector3" then
		return com
	end
	return part.CFrame.Position
end

local function getSafeName(p: PartData): string
	return p.Name or ""
end

local function getSafeTex(p: PartData): string
	return p.TextureId or ""
end

function Serializer.Serialize(payload: MapPayload): buffer
	local total = computeTotalSize(payload)
	local buf = bcreate(total)
	local off = 0

	writeu8(buf, off, VERSION); off = off + 1

	local originPos = payload.OriginPosition or Vector3.zero
	writef32(buf, off, originPos.X); off = off + 4
	writef32(buf, off, originPos.Y); off = off + 4
	writef32(buf, off, originPos.Z); off = off + 4

	local originRot = payload.OriginRotation or CFrame.identity
	local rx, ry, rz = originRot:ToOrientation()
	writef32(buf, off, rx); off = off + 4
	writef32(buf, off, ry); off = off + 4
	writef32(buf, off, rz); off = off + 4

	local ms = payload.ModelSize or Vector3.zero
	writef32(buf, off, ms.X); off = off + 4
	writef32(buf, off, ms.Y); off = off + 4
	writef32(buf, off, ms.Z); off = off + 4

	writef32(buf, off, payload.VoxelSize or 2); off = off + 4

	local meshes = payload.Meshes or {}
	local parts = payload.Parts or {}
	local boxes = payload.Boxes or {}
	local welds = payload.Welds or {}

	writeu32(buf, off, #meshes); off = off + 4
	writeu32(buf, off, #parts); off = off + 4
	writeu32(buf, off, #boxes); off = off + 4
	writeu32(buf, off, #welds); off = off + 4

	for i = 1, #meshes do
		local m = meshes[i]
		local meshId = m.MeshId or ""
		if #meshId > MAX_STR_LEN then meshId = stringSub(meshId, 1, MAX_STR_LEN) end
		local texId = m.TextureId or ""
		if #texId > MAX_STR_LEN then texId = stringSub(texId, 1, MAX_STR_LEN) end

		writeu8(buf, off, #meshId); off = off + 1
		if #meshId > 0 then writestr(buf, off, meshId); off = off + #meshId end
		writeu8(buf, off, #texId); off = off + 1
		if #texId > 0 then writestr(buf, off, texId); off = off + #texId end

		local scale = m.Scale or Vector3.one
		writef32(buf, off, scale.X); off = off + 4
		writef32(buf, off, scale.Y); off = off + 4
		writef32(buf, off, scale.Z); off = off + 4
	end

	for i = 1, #parts do
		local p = parts[i]
		local name = getSafeName(p)
		if #name > MAX_STR_LEN then name = stringSub(name, 1, MAX_STR_LEN) end
		local texId = getSafeTex(p)
		if #texId > MAX_STR_LEN then texId = stringSub(texId, 1, MAX_STR_LEN) end

		writeu8(buf, off, #name); off = off + 1
		if #name > 0 then writestr(buf, off, name); off = off + #name end
		writeu8(buf, off, #texId); off = off + 1
		if #texId > 0 then writestr(buf, off, texId); off = off + #texId end

		writeu8(buf, off, clampByte(p.Category or 1)); off = off + 1
		writeu16(buf, off, mathround(p.Material or 0)); off = off + 2
		writeu16(buf, off, mathround(p.MeshIndex or 0)); off = off + 2

		local col = p.Color or Color3.new(1, 1, 1)
		writeu8(buf, off, clampByte(col.R * 255)); off = off + 1
		writeu8(buf, off, clampByte(col.G * 255)); off = off + 1
		writeu8(buf, off, clampByte(col.B * 255)); off = off + 1

		local cf = p.CFrame
		local pos = cf.Position
		writef32(buf, off, pos.X); off = off + 4
		writef32(buf, off, pos.Y); off = off + 4
		writef32(buf, off, pos.Z); off = off + 4

		local px, py, pz = cf:ToOrientation()
		writef32(buf, off, px); off = off + 4
		writef32(buf, off, py); off = off + 4
		writef32(buf, off, pz); off = off + 4

		local sz = p.Size
		writef32(buf, off, sz.X); off = off + 4
		writef32(buf, off, sz.Y); off = off + 4
		writef32(buf, off, sz.Z); off = off + 4

		writef32(buf, off, p.Mass or 0); off = off + 4

		local com = getSafeCOM(p)
		writef32(buf, off, com.X); off = off + 4
		writef32(buf, off, com.Y); off = off + 4
		writef32(buf, off, com.Z); off = off + 4

		writef32(buf, off, p.HP or 100); off = off + 4
		writef32(buf, off, p.Hardness or 1); off = off + 4
		writef32(buf, off, p.ForceTransmission or 1); off = off + 4
		writef32(buf, off, p.StressResistance or 1); off = off + 4
		writef32(buf, off, p.TensileStrength or 150); off = off + 4
		writef32(buf, off, p.BendingForce or 300); off = off + 4
		writef32(buf, off, p.CompressionStrength or 800); off = off + 4
		writef32(buf, off, p.Pressure or 1); off = off + 4

		writeu8(buf, off, p.IsAnchor and 1 or 0); off = off + 1
		writeu8(buf, off, (p.IsDestructible ~= false) and 1 or 0); off = off + 1

		local odc = ON_DISCONNECT_ENCODE[p.OnDisconnect or "Auto"]
		if odc == nil then odc = 0 end
		writeu8(buf, off, odc); off = off + 1

		writef32(buf, off, p.BreakRadius or 4); off = off + 4
		writef32(buf, off, p.ShatterAirPercent or 0.5); off = off + 4
		writeu16(buf, off, mathround(p.MaxDebrisPerPart or 64)); off = off + 2
		writef32(buf, off, p.UnweldPercentage or 0.6); off = off + 4

		writeu8(buf, off, p.IsFalling and 1 or 0); off = off + 1
		writeu32(buf, off, mathround(p.ClusterId or 0)); off = off + 4
	end

	for i = 1, #boxes do
		local b = boxes[i]
		writeu32(buf, off, mathround(b.GlobalId or 0)); off = off + 4

		local bp = b.Pos or Vector3.zero
		writef32(buf, off, bp.X); off = off + 4
		writef32(buf, off, bp.Y); off = off + 4
		writef32(buf, off, bp.Z); off = off + 4

		local bs = b.Size or Vector3.one
		writef32(buf, off, bs.X); off = off + 4
		writef32(buf, off, bs.Y); off = off + 4
		writef32(buf, off, bs.Z); off = off + 4

		writeu16(buf, off, mathround(b.PartIndex or 0)); off = off + 2
		writef32(buf, off, b.DamageSeed or 0); off = off + 4
	end

	for i = 1, #welds do
		local w = welds[i]
		writeu16(buf, off, mathround(w.PartA or 0)); off = off + 2
		writeu16(buf, off, mathround(w.PartB or 0)); off = off + 2

		local oa = w.OffsetA or Vector3.zero
		writef32(buf, off, oa.X); off = off + 4
		writef32(buf, off, oa.Y); off = off + 4
		writef32(buf, off, oa.Z); off = off + 4

		local ob = w.OffsetB or Vector3.zero
		writef32(buf, off, ob.X); off = off + 4
		writef32(buf, off, ob.Y); off = off + 4
		writef32(buf, off, ob.Z); off = off + 4

		writef32(buf, off, w.DamageSeed or 0); off = off + 4
	end

	return buf
end

function Serializer.Deserialize(buf: buffer): MapPayload
	local off = 0
	local version = readu8(buf, off); off = off + 1

	assert(
		version >= VERSION_MIN and version <= VERSION,
		stringFmt(
			"Serializer: unsupported version %d (min=%d, max=%d)",
			version, VERSION_MIN, VERSION
		)
	)

	local opx = readf32(buf, off); off = off + 4
	local opy = readf32(buf, off); off = off + 4
	local opz = readf32(buf, off); off = off + 4

	local orx = readf32(buf, off); off = off + 4
	local ory = readf32(buf, off); off = off + 4
	local orz = readf32(buf, off); off = off + 4

	local msx = readf32(buf, off); off = off + 4
	local msy = readf32(buf, off); off = off + 4
	local msz = readf32(buf, off); off = off + 4

	local vsize = readf32(buf, off); off = off + 4

	local nMeshes = readu32(buf, off); off = off + 4
	local nParts  = readu32(buf, off); off = off + 4
	local nBoxes  = readu32(buf, off); off = off + 4
	local nWelds  = readu32(buf, off); off = off + 4

	local meshes = table.create(nMeshes)
	for i = 1, nMeshes do
		local ml = readu8(buf, off); off = off + 1
		local meshId = ""
		if ml > 0 then meshId = readstr(buf, off, ml); off = off + ml end
		local tl = readu8(buf, off); off = off + 1
		local texId = ""
		if tl > 0 then texId = readstr(buf, off, tl); off = off + tl end
		local sx = readf32(buf, off); off = off + 4
		local sy = readf32(buf, off); off = off + 4
		local sz = readf32(buf, off); off = off + 4
		meshes[i] = { MeshId = meshId, TextureId = texId, Scale = Vector3.new(sx, sy, sz) }
	end

	local parts = table.create(nParts)
	for i = 1, nParts do
		local nl = readu8(buf, off); off = off + 1
		local name = ""
		if nl > 0 then name = readstr(buf, off, nl); off = off + nl end
		local tl = readu8(buf, off); off = off + 1
		local texId = ""
		if tl > 0 then texId = readstr(buf, off, tl); off = off + tl end

		local category = readu8(buf, off); off = off + 1
		local material = readu16(buf, off); off = off + 2
		local meshIndex = readu16(buf, off); off = off + 2

		local cr = readu8(buf, off); off = off + 1
		local cg = readu8(buf, off); off = off + 1
		local cb = readu8(buf, off); off = off + 1

		local px = readf32(buf, off); off = off + 4
		local py = readf32(buf, off); off = off + 4
		local pz = readf32(buf, off); off = off + 4
		local rx = readf32(buf, off); off = off + 4
		local ry = readf32(buf, off); off = off + 4
		local rz = readf32(buf, off); off = off + 4

		local sx = readf32(buf, off); off = off + 4
		local sy = readf32(buf, off); off = off + 4
		local sz = readf32(buf, off); off = off + 4

		local mass = readf32(buf, off); off = off + 4

		local comx = readf32(buf, off); off = off + 4
		local comy = readf32(buf, off); off = off + 4
		local comz = readf32(buf, off); off = off + 4

		local hp = readf32(buf, off); off = off + 4
		local hard = readf32(buf, off); off = off + 4
		local ft = readf32(buf, off); off = off + 4
		local sr = readf32(buf, off); off = off + 4
		local tens = readf32(buf, off); off = off + 4
		local bend = readf32(buf, off); off = off + 4
		local comp = readf32(buf, off); off = off + 4
		local press = readf32(buf, off); off = off + 4

		local isAnchor = readu8(buf, off) ~= 0; off = off + 1
		local isDestructible = readu8(buf, off) ~= 0; off = off + 1
		local odc = readu8(buf, off); off = off + 1

		local breakRad = readf32(buf, off); off = off + 4
		local shatterPct = readf32(buf, off); off = off + 4
		local maxDebris = readu16(buf, off); off = off + 2
		local unweldPct = readf32(buf, off); off = off + 4

		local isFalling = false
		local clusterId = 0
		if version >= 4 then
			isFalling = readu8(buf, off) ~= 0; off = off + 1
			clusterId = readu32(buf, off); off = off + 4
		end

		parts[i] = {
			Name = name,
			CFrame = CFrame.new(px, py, pz) * CFrame.fromOrientation(rx, ry, rz),
			Size = Vector3.new(sx, sy, sz),
			Mass = mass,
			CenterOfMass = Vector3.new(comx, comy, comz),
			Category = category,
			Material = material,
			Color = Color3.fromRGB(cr, cg, cb),
			TextureId = texId,
			MeshIndex = meshIndex,
			HP = hp,
			Hardness = hard,
			ForceTransmission = ft,
			StressResistance = sr,
			TensileStrength = tens,
			BendingForce = bend,
			CompressionStrength = comp,
			Pressure = press,
			IsAnchor = isAnchor,
			IsDestructible = isDestructible,
			OnDisconnect = ON_DISCONNECT_DECODE[odc + 1] or "Auto",
			BreakRadius = breakRad,
			ShatterAirPercent = shatterPct,
			MaxDebrisPerPart = maxDebris,
			UnweldPercentage = unweldPct,
			IsFalling = isFalling,
			ClusterId = clusterId,
		}
	end

	local boxes = table.create(nBoxes)
	for i = 1, nBoxes do
		local gid = readu32(buf, off); off = off + 4
		local bx = readf32(buf, off); off = off + 4
		local by = readf32(buf, off); off = off + 4
		local bz = readf32(buf, off); off = off + 4
		local bsx = readf32(buf, off); off = off + 4
		local bsy = readf32(buf, off); off = off + 4
		local bsz = readf32(buf, off); off = off + 4
		local partIndex = readu16(buf, off); off = off + 2

		local damageSeed = 0
		if version >= 4 then
			damageSeed = readf32(buf, off); off = off + 4
		end

		boxes[i] = {
			GlobalId = gid,
			Pos = Vector3.new(bx, by, bz),
			Size = Vector3.new(bsx, bsy, bsz),
			PartIndex = partIndex,
			DamageSeed = damageSeed,
		}
	end

	local welds = table.create(nWelds)
	for i = 1, nWelds do
		local pa = readu16(buf, off); off = off + 2
		local pb = readu16(buf, off); off = off + 2
		local oax = readf32(buf, off); off = off + 4
		local oay = readf32(buf, off); off = off + 4
		local oaz = readf32(buf, off); off = off + 4
		local obx = readf32(buf, off); off = off + 4
		local oby = readf32(buf, off); off = off + 4
		local obz = readf32(buf, off); off = off + 4

		local damageSeed = 0
		if version >= 4 then
			damageSeed = readf32(buf, off); off = off + 4
		end

		welds[i] = {
			PartA = pa,
			PartB = pb,
			OffsetA = Vector3.new(oax, oay, oaz),
			OffsetB = Vector3.new(obx, oby, obz),
			DamageSeed = damageSeed,
		}
	end

	return {
		OriginPosition = Vector3.new(opx, opy, opz),
		OriginRotation = CFrame.fromOrientation(orx, ory, orz),
		ModelSize = Vector3.new(msx, msy, msz),
		VoxelSize = vsize,
		Meshes = meshes,
		Parts = parts,
		Boxes = boxes,
		Welds = welds,
	}
end

return Serializer

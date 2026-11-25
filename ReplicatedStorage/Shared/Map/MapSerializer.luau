--!strict
--!native

local MapLoaderConfig = require(script.Parent.MapLoaderConfig)

local CFG = MapLoaderConfig
local writeu8   = buffer.writeu8
local writeu16  = buffer.writeu16
local writeu32  = buffer.writeu32
local writef32  = buffer.writef32
local writestr  = buffer.writestring
local readu8    = buffer.readu8
local readu16   = buffer.readu16
local readu32   = buffer.readu32
local readf32   = buffer.readf32
local readstr   = buffer.readstring
local bcreate   = buffer.create

local mathround = math.round
local mathclamp = math.clamp

local MapSerializer = {}

export type PartData = {
	Name: string, CFrame: CFrame, Size: Vector3, Color: Color3,
	Material: number, PartIndex: number,
	Mass: number, HP: number,
	TensileStrength: number, BendingForce: number, CompressionStrength: number,
	IsAnchor: boolean?, IsDestructible: boolean?,
	OnDisconnect: string?, BreakRadius: number?,
	ShatterAirPercent: number?, MaxDebrisPerPart: number?,
	ForceTransmission: number?, UnweldPercentage: number?,
}
export type DebrisData = {
	Id: number, CFrame: CFrame, Size: Vector3, Color: Color3, Material: number,
}

local MAX_NAME       = 50
local PART_BASE_BYTES = 87
local DEBRIS_BYTES    = 45

local ON_DISCONNECT_ENCODE: { [string]: number } = {
	["Auto"] = 0, ["Ignore"] = 1, ["Detach"] = 2, ["Break"] = 3, ["Shatter"] = 4,
}
local ON_DISCONNECT_DECODE: { string } = {
	"Auto", "Ignore", "Detach", "Break", "Shatter",
}

local function encodeColorByte(c: number): number
	local v = mathround(c * 255)
	if v < 0 then return 0 end
	if v > 255 then return 255 end
	return v
end

local function computeMapBufferSize(parts: { [number]: PartData }): (number, number)
	local count = 0
	local size = 4
	for _, p in pairs(parts) do
		count = count + 1
		local nameLen = #(p.Name or "")
		if nameLen > MAX_NAME then nameLen = MAX_NAME end
		size = size + PART_BASE_BYTES + nameLen
	end
	return size, count
end

function MapSerializer.SerializeMap(parts: { [number]: PartData }): buffer
	local size, count = computeMapBufferSize(parts)
	local buf = bcreate(size)
	local off = 0

	writeu32(buf, off, count)
	off = off + 4

	for _, p in pairs(parts) do
		local name = p.Name or ""
		local nameLen = #name
		if nameLen > MAX_NAME then
			nameLen = MAX_NAME
			name = name:sub(1, MAX_NAME)
		end

		writeu8(buf, off, nameLen)
		off = off + 1
		if nameLen > 0 then
			writestr(buf, off, name)
			off = off + nameLen
		end

		local cf = p.CFrame
		local pos = cf.Position
		writef32(buf, off, pos.X); off = off + 4
		writef32(buf, off, pos.Y); off = off + 4
		writef32(buf, off, pos.Z); off = off + 4

		local rx, ry, rz = cf:ToOrientation()
		writef32(buf, off, rx); off = off + 4
		writef32(buf, off, ry); off = off + 4
		writef32(buf, off, rz); off = off + 4

		local sz = p.Size
		writef32(buf, off, sz.X); off = off + 4
		writef32(buf, off, sz.Y); off = off + 4
		writef32(buf, off, sz.Z); off = off + 4

		local col = p.Color
		writeu8(buf, off, encodeColorByte(col.R)); off = off + 1
		writeu8(buf, off, encodeColorByte(col.G)); off = off + 1
		writeu8(buf, off, encodeColorByte(col.B)); off = off + 1

		writeu16(buf, off, mathround(p.Material or 0)); off = off + 2
		writeu32(buf, off, mathround(p.PartIndex or 0)); off = off + 4

		writef32(buf, off, p.Mass or 0); off = off + 4
		writef32(buf, off, p.HP or 100); off = off + 4
		writef32(buf, off, p.TensileStrength or 150); off = off + 4
		writef32(buf, off, p.BendingForce or 300); off = off + 4
		writef32(buf, off, p.CompressionStrength or 800); off = off + 4

		local isAnchor = p.IsAnchor == true
		local isDestructible = (p.IsDestructible ~= false)
		writeu8(buf, off, isAnchor and 1 or 0); off = off + 1
		writeu8(buf, off, isDestructible and 1 or 0); off = off + 1

		local odc = ON_DISCONNECT_ENCODE[p.OnDisconnect or "Auto"]
		if odc == nil then odc = 0 end
		writeu8(buf, off, odc); off = off + 1

		writef32(buf, off, p.BreakRadius or 4.0); off = off + 4
		writef32(buf, off, p.ShatterAirPercent or 0.5); off = off + 4
		writeu16(buf, off, mathround(p.MaxDebrisPerPart or 64)); off = off + 2
		writef32(buf, off, p.ForceTransmission or 1.0); off = off + 4
		writef32(buf, off, p.UnweldPercentage or 0.6); off = off + 4
	end

	return buf
end

function MapSerializer.DeserializeMap(buf: buffer, version: number?): { [number]: PartData }
	local ver = version or (CFG and CFG.SERIALIZER_VERSION) or 3

	local count = readu32(buf, 0)
	local off = 4
	local out: { [number]: PartData } = {}

	for _ = 1, count do
		local nameLen = readu8(buf, off); off = off + 1
		local name = ""
		if nameLen > 0 then
			name = readstr(buf, off, nameLen)
			off = off + nameLen
		end

		local px = readf32(buf, off); off = off + 4
		local py = readf32(buf, off); off = off + 4
		local pz = readf32(buf, off); off = off + 4
		local rx = readf32(buf, off); off = off + 4
		local ry = readf32(buf, off); off = off + 4
		local rz = readf32(buf, off); off = off + 4

		local sx = readf32(buf, off); off = off + 4
		local sy = readf32(buf, off); off = off + 4
		local sz = readf32(buf, off); off = off + 4

		local cr = readu8(buf, off); off = off + 1
		local cg = readu8(buf, off); off = off + 1
		local cb = readu8(buf, off); off = off + 1

		local mat = readu16(buf, off); off = off + 2
		local partIndex = readu32(buf, off); off = off + 4

		local mass = readf32(buf, off); off = off + 4
		local hp = readf32(buf, off); off = off + 4
		local tens = readf32(buf, off); off = off + 4
		local bend = readf32(buf, off); off = off + 4
		local comp = readf32(buf, off); off = off + 4

		local isAnchor = readu8(buf, off) ~= 0; off = off + 1
		local isDestructible = readu8(buf, off) ~= 0; off = off + 1
		local odc = readu8(buf, off); off = off + 1

		local brkR = readf32(buf, off); off = off + 4
		local shPct = readf32(buf, off); off = off + 4
		local maxD = readu16(buf, off); off = off + 2
		local ft = readf32(buf, off); off = off + 4
		local uw = readf32(buf, off); off = off + 4

		if ver < 3 then
			ft = 1.0
			uw = 0.6
		end

		local onDisc = ON_DISCONNECT_DECODE[odc + 1] or "Auto"

		out[partIndex] = {
			Name = name,
			CFrame = CFrame.new(px, py, pz) * CFrame.fromOrientation(rx, ry, rz),
			Size = Vector3.new(sx, sy, sz),
			Color = Color3.fromRGB(cr, cg, cb),
			Material = mat,
			PartIndex = partIndex,
			Mass = mass,
			HP = hp,
			TensileStrength = tens,
			BendingForce = bend,
			CompressionStrength = comp,
			IsAnchor = isAnchor,
			IsDestructible = isDestructible,
			OnDisconnect = onDisc,
			BreakRadius = brkR,
			ShatterAirPercent = shPct,
			MaxDebrisPerPart = maxD,
			ForceTransmission = ft,
			UnweldPercentage = uw,
		}
	end

	return out
end

function MapSerializer.SerializeDebris(debris: { DebrisData }): buffer
	local n = #debris
	local buf = bcreate(4 + n * DEBRIS_BYTES)
	local off = 0

	writeu32(buf, off, n)
	off = off + 4

	for i = 1, n do
		local d = debris[i]

		local id = d.Id
		if typeof(id) ~= "number" then id = 0 end
		writeu32(buf, off, mathround(id)); off = off + 4

		local cf = d.CFrame
		local pos = cf.Position
		writef32(buf, off, pos.X); off = off + 4
		writef32(buf, off, pos.Y); off = off + 4
		writef32(buf, off, pos.Z); off = off + 4

		local rx, ry, rz = cf:ToOrientation()
		writef32(buf, off, rx); off = off + 4
		writef32(buf, off, ry); off = off + 4
		writef32(buf, off, rz); off = off + 4

		local sz = d.Size
		writef32(buf, off, sz.X); off = off + 4
		writef32(buf, off, sz.Y); off = off + 4
		writef32(buf, off, sz.Z); off = off + 4

		local col = d.Color
		writeu8(buf, off, encodeColorByte(col.R)); off = off + 1
		writeu8(buf, off, encodeColorByte(col.G)); off = off + 1
		writeu8(buf, off, encodeColorByte(col.B)); off = off + 1

		local matVal = d.Material
		if typeof(matVal) == "EnumItem" then
			matVal = matVal.Value
		elseif type(matVal) ~= "number" then
			matVal = 0
		end
		writeu16(buf, off, mathround(matVal)); off = off + 2
	end

	return buf
end

function MapSerializer.DeserializeDebris(buf: buffer): { DebrisData }
	local n = readu32(buf, 0)
	local off = 4
	local out: { DebrisData } = {}

	for i = 1, n do
		local id = readu32(buf, off); off = off + 4

		local px = readf32(buf, off); off = off + 4
		local py = readf32(buf, off); off = off + 4
		local pz = readf32(buf, off); off = off + 4

		local rx = readf32(buf, off); off = off + 4
		local ry = readf32(buf, off); off = off + 4
		local rz = readf32(buf, off); off = off + 4

		local sx = readf32(buf, off); off = off + 4
		local sy = readf32(buf, off); off = off + 4
		local sz = readf32(buf, off); off = off + 4

		local cr = readu8(buf, off); off = off + 1
		local cg = readu8(buf, off); off = off + 1
		local cb = readu8(buf, off); off = off + 1

		local mat = readu16(buf, off); off = off + 2

		out[i] = {
			Id = id,
			CFrame = CFrame.new(px, py, pz) * CFrame.fromOrientation(rx, ry, rz),
			Size = Vector3.new(sx, sy, sz),
			Color = Color3.fromRGB(cr, cg, cb),
			Material = mat,
		}
	end

	return out
end

return MapSerializer

--!strict
--!native

--
--   record: u32 id | u8 flags | u8 shape | u16 material | u8 r g b | u8 transparency(x255)
--           f32 sx sy sz | f32 px py pz | f32 rx ry rz (CFrame:ToOrientation)
--   shape : 0 Block | 1 Ball | 2 Cylinder

local readu8, writeu8 = buffer.readu8, buffer.writeu8
local readu16, writeu16 = buffer.readu16, buffer.writeu16
local readu32, writeu32 = buffer.readu32, buffer.writeu32
local readf32, writef32 = buffer.readf32, buffer.writef32
local floor, clamp = math.floor, math.clamp
local band = bit32.band

local SpawnCodec = {}
SpawnCodec.RecordBytes = 48

function SpawnCodec.Write(buf: buffer, off: number, part: BasePart, id: number, mapOrigin: boolean, immediate: boolean?)
	local flags = 0
	if mapOrigin then flags += 1 end
	if immediate then flags += 8 end
	if part.CanCollide then flags += 2 end

	local shape = 0
	if part:IsA("Part") then
		local s = (part :: any).Shape
		if s == Enum.PartType.Ball then
			shape = 1
		elseif s == Enum.PartType.Cylinder then
			shape = 2
		end
	else
		flags += 4
	end

	writeu32(buf, off, id)
	writeu8(buf, off + 4, flags)
	writeu8(buf, off + 5, shape)
	writeu16(buf, off + 6, part.Material.Value)

	local c = part.Color
	writeu8(buf, off + 8, floor(c.R * 255 + 0.5))
	writeu8(buf, off + 9, floor(c.G * 255 + 0.5))
	writeu8(buf, off + 10, floor(c.B * 255 + 0.5))
	writeu8(buf, off + 11, floor(clamp(part.Transparency, 0, 1) * 255 + 0.5))

	local s = part.Size
	writef32(buf, off + 12, s.X)
	writef32(buf, off + 16, s.Y)
	writef32(buf, off + 20, s.Z)

	local cf = part.CFrame
	local p = cf.Position
	writef32(buf, off + 24, p.X)
	writef32(buf, off + 28, p.Y)
	writef32(buf, off + 32, p.Z)
	local rx, ry, rz = cf:ToOrientation()
	writef32(buf, off + 36, rx)
	writef32(buf, off + 40, ry)
	writef32(buf, off + 44, rz)
end

function SpawnCodec.Read(buf: buffer, off: number): { [string]: any }
	local flags = readu8(buf, off + 4)
	local ok, mat = pcall(function()
		return (Enum.Material :: any):FromValue(readu16(buf, off + 6))
	end)
	return {
		id = readu32(buf, off),
		mapOrigin = band(flags, 1) ~= 0,
		canCollide = band(flags, 2) ~= 0,
		noProxy = band(flags, 4) ~= 0,
		immediate = band(flags, 8) ~= 0,
		shape = readu8(buf, off + 5),
		material = if ok and mat then mat else Enum.Material.Plastic,
		color = Color3.fromRGB(readu8(buf, off + 8), readu8(buf, off + 9), readu8(buf, off + 10)),
		transparency = readu8(buf, off + 11) / 255,
		size = Vector3.new(readf32(buf, off + 12), readf32(buf, off + 16), readf32(buf, off + 20)),
		cf = CFrame.new(readf32(buf, off + 24), readf32(buf, off + 28), readf32(buf, off + 32))
			* CFrame.fromOrientation(readf32(buf, off + 36), readf32(buf, off + 40), readf32(buf, off + 44)),
	}
end

function SpawnCodec.Count(buf: buffer): number
	if buffer.len(buf) < 2 then return 0 end
	return readu16(buf, 0)
end

function SpawnCodec.EncodeIds(ids: { number }, from: number, to: number): buffer
	local n = to - from + 1
	local buf = buffer.create(2 + n * 4)
	writeu16(buf, 0, n)
	for i = 0, n - 1 do
		writeu32(buf, 2 + i * 4, ids[from + i])
	end
	return buf
end

function SpawnCodec.DecodeIds(buf: buffer): { number }
	local out: { number } = {}
	local n = SpawnCodec.Count(buf)
	if buffer.len(buf) < 2 + n * 4 then return out end
	for i = 0, n - 1 do
		out[i + 1] = readu32(buf, 2 + i * 4)
	end
	return out
end

return SpawnCodec

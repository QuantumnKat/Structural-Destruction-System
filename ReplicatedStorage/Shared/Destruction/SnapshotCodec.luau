--!strict
--!native

--
--
--   pose = u32 partIndex + i16 x6 (Quantize.CFrameToInt16)

local readu8, writeu8 = buffer.readu8, buffer.writeu8
local readu16, writeu16 = buffer.readu16, buffer.writeu16
local readu32, writeu32 = buffer.readu32, buffer.writeu32
local bcreate, bcopy, blen = buffer.create, buffer.copy, buffer.len
local band, bor, bnot, lshift, rshift = bit32.band, bit32.bor, bit32.bnot, bit32.lshift, bit32.rshift

local SnapshotCodec = {}

local MAGIC = 0x50414E53 -- "SNAP"
local HEADER = 19
SnapshotCodec.PoseBytes = 16

function SnapshotCodec.StateBytes(maxIdx: number): number
	return (maxIdx + 3) // 4
end

function SnapshotCodec.GetState(buf: buffer, idx: number): number
	local i = idx - 1
	local byte = readu8(buf, i // 4)
	return band(rshift(byte, (i % 4) * 2), 3)
end

function SnapshotCodec.SetState(buf: buffer, idx: number, state: number)
	local i = idx - 1
	local bi = i // 4
	local shift = (i % 4) * 2
	local byte = readu8(buf, bi)
	byte = bor(band(byte, bnot(lshift(3, shift))), lshift(state, shift))
	writeu8(buf, bi, band(byte, 255))
end

function SnapshotCodec.RleEncode(src: buffer): buffer
	local n = blen(src)

	local size = 0
	local i = 0
	while i < n do
		if readu8(src, i) == 0 then
			local run = 1
			while i + run < n and run < 255 and readu8(src, i + run) == 0 do run += 1 end
			size += 2
			i += run
		else
			size += 1
			i += 1
		end
	end

	local out = bcreate(size)
	local o = 0
	i = 0
	while i < n do
		local b = readu8(src, i)
		if b == 0 then
			local run = 1
			while i + run < n and run < 255 and readu8(src, i + run) == 0 do run += 1 end
			writeu8(out, o, 0)
			writeu8(out, o + 1, run)
			o += 2
			i += run
		else
			writeu8(out, o, b)
			o += 1
			i += 1
		end
	end
	return out
end

function SnapshotCodec.RleDecode(src: buffer, srcOff: number, srcLen: number, outLen: number): buffer
	local out = bcreate(outLen)
	local o = 0
	local i = 0
	while i < srcLen and o < outLen do
		local b = readu8(src, srcOff + i)
		if b == 0 then
			local run = readu8(src, srcOff + i + 1)
			o += run
			i += 2
		else
			writeu8(out, o, b)
			o += 1
			i += 1
		end
	end
	return out
end

function SnapshotCodec.Pack(maxIdx: number, seq: number, rle: buffer, poses: buffer?, poseCount: number): buffer
	poseCount = math.clamp(poseCount, 0, 65535)
	local rleLen = blen(rle)
	local out = bcreate(HEADER + rleLen + poseCount * 16)
	writeu32(out, 0, MAGIC)
	writeu8(out, 4, 1)
	writeu32(out, 5, maxIdx)
	writeu32(out, 9, seq)
	writeu32(out, 13, rleLen)
	writeu16(out, 17, poseCount)
	bcopy(out, HEADER, rle, 0, rleLen)
	if poses and poseCount > 0 then
		bcopy(out, HEADER + rleLen, poses, 0, poseCount * 16)
	end
	return out
end

function SnapshotCodec.Unpack(buf: buffer): (number?, number?, buffer?, buffer?, number)
	if blen(buf) < HEADER or readu32(buf, 0) ~= MAGIC then
		return nil, nil, nil, nil, 0
	end
	local maxIdx = readu32(buf, 5)
	local seq = readu32(buf, 9)
	local rleLen = readu32(buf, 13)
	local poseCount = readu16(buf, 17)
	if HEADER + rleLen + poseCount * 16 > blen(buf) then
		return nil, nil, nil, nil, 0
	end

	local state = SnapshotCodec.RleDecode(buf, HEADER, rleLen, SnapshotCodec.StateBytes(maxIdx))
	local poses: buffer? = nil
	if poseCount > 0 then
		poses = bcreate(poseCount * 16)
		bcopy(poses :: buffer, 0, buf, HEADER + rleLen, poseCount * 16)
	end
	return maxIdx, seq, state, poses, poseCount
end

return SnapshotCodec

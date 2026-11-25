--!strict
--!native

--
--   HIT      (34B)  ms, shapeCode, pos f32x3, force f32, look i16x3, params u16x3 (x0.1 stud)
--   COLLAPSE ( 7B)  ms, count u16
--   FRAGMENT (34B)  ms, fid u32, n u16, flags u8 (bit0 = welded), mass f32, com f32x3, vel i16x3 (x0.1)
--   VANISH   ( 9B)  ms, id u32
--   DESTROY  ( 9B)  ms, partIndex u32
--   SPLIT    (10B)  ms, id u32, pieces u8

local writeu8, writeu16, writeu32 = buffer.writeu8, buffer.writeu16, buffer.writeu32
local writei16, writef32, writef64 = buffer.writei16, buffer.writef32, buffer.writef64
local readu8, readu16, readu32 = buffer.readu8, buffer.readu16, buffer.readu32
local readi16, readf32, readf64 = buffer.readi16, buffer.readf32, buffer.readf64
local bcreate, bcopy, blen = buffer.create, buffer.copy, buffer.len

local mathclamp, floor = math.clamp, math.floor

local EventLog = {}
EventLog.__index = EventLog

EventLog.HIT = 1
EventLog.COLLAPSE = 2
EventLog.FRAGMENT = 3
EventLog.VANISH = 4
EventLog.DESTROY = 5
EventLog.SPLIT = 6

EventLog.ShapeCode = { Sphere = 1, Box = 2, Capsule = 3, Cylinder = 4, Cone = 5, Line = 6 }

local SIZES: { [number]: number } = { 34, 7, 34, 9, 9, 10 }
EventLog.Sizes = SIZES

local MAGIC = 0x474F4C46 -- "FLOG"

local function q16(x: number): number
	return mathclamp(floor(x * 32767 + 0.5), -32767, 32767)
end

local function u16(x: number): number
	return mathclamp(floor(x + 0.5), 0, 65535)
end

local function nowMs(self: any): number
	return mathclamp(floor((workspace:GetServerTimeNow() - self.Base) * 1000), 0, 4294967295)
end

local function reserve(self: any, size: number): (buffer, number)
	local cur: number = self.Cur
	local seg: buffer? = self.Segs[cur]
	if seg == nil then
		seg = bcreate(self.SegBytes)
		self.Segs[cur] = seg
		self.Used[cur] = 0
		self.Counts[cur] = 0
		self.FirstSeq[cur] = self.Seq + 1
	end
	local used: number = self.Used[cur]
	if used + size > self.SegBytes then
		cur = cur % self.SegCount + 1
		self.Cur = cur
		local old: buffer? = self.Segs[cur]
		if old ~= nil then
			self.Dropped += self.Counts[cur] or 0
			seg = old
		else
			seg = bcreate(self.SegBytes)
			self.Segs[cur] = seg
		end
		self.Used[cur] = 0
		self.Counts[cur] = 0
		self.FirstSeq[cur] = self.Seq + 1
		used = 0
	end
	self.Used[cur] = used + size
	self.Counts[cur] += 1
	self.Seq += 1
	return seg :: buffer, used
end

function EventLog.new(segmentBytes: number, segments: number): any
	local self: any = setmetatable({}, EventLog)
	self.SegBytes = math.max(256, math.floor(segmentBytes))
	self.SegCount = math.max(2, math.floor(segments))
	self.Segs = {}
	self.Used = {}
	self.Counts = {}
	self.FirstSeq = {}
	self.Cur = 1
	self.Seq = 0
	self.Dropped = 0
	self.Base = workspace:GetServerTimeNow()
	return self
end

function EventLog:Hit(code: number, pos: Vector3, force: number, look: Vector3, p1: number, p2: number, p3: number)
	local b, o = reserve(self, 34)
	writeu8(b, o, 1)
	writeu32(b, o + 1, nowMs(self))
	writeu8(b, o + 5, code)
	writef32(b, o + 6, pos.X)
	writef32(b, o + 10, pos.Y)
	writef32(b, o + 14, pos.Z)
	writef32(b, o + 18, force)
	writei16(b, o + 22, q16(look.X))
	writei16(b, o + 24, q16(look.Y))
	writei16(b, o + 26, q16(look.Z))
	writeu16(b, o + 28, u16(p1 * 10))
	writeu16(b, o + 30, u16(p2 * 10))
	writeu16(b, o + 32, u16(p3 * 10))
end

function EventLog:Collapse(count: number)
	local b, o = reserve(self, 7)
	writeu8(b, o, 2)
	writeu32(b, o + 1, nowMs(self))
	writeu16(b, o + 5, mathclamp(count, 0, 65535))
end

function EventLog:Fragment(fid: number, n: number, welded: boolean, mass: number, com: Vector3, vel: Vector3)
	local b, o = reserve(self, 34)
	writeu8(b, o, 3)
	writeu32(b, o + 1, nowMs(self))
	writeu32(b, o + 5, fid)
	writeu16(b, o + 9, mathclamp(n, 0, 65535))
	writeu8(b, o + 11, if welded then 1 else 0)
	writef32(b, o + 12, mass)
	writef32(b, o + 16, com.X)
	writef32(b, o + 20, com.Y)
	writef32(b, o + 24, com.Z)
	writei16(b, o + 28, mathclamp(floor(vel.X * 10 + 0.5), -32767, 32767))
	writei16(b, o + 30, mathclamp(floor(vel.Y * 10 + 0.5), -32767, 32767))
	writei16(b, o + 32, mathclamp(floor(vel.Z * 10 + 0.5), -32767, 32767))
end

function EventLog:Vanish(id: number)
	local b, o = reserve(self, 9)
	writeu8(b, o, 4)
	writeu32(b, o + 1, nowMs(self))
	writeu32(b, o + 5, id)
end

function EventLog:Destroy(partIndex: number)
	local b, o = reserve(self, 9)
	writeu8(b, o, 5)
	writeu32(b, o + 1, nowMs(self))
	writeu32(b, o + 5, partIndex)
end

function EventLog:Split(id: number, pieces: number)
	local b, o = reserve(self, 10)
	writeu8(b, o, 6)
	writeu32(b, o + 1, nowMs(self))
	writeu32(b, o + 5, id)
	writeu8(b, o + 9, mathclamp(pieces, 0, 255))
end

function EventLog:ForEach(fn: (number, number, buffer, number) -> ())
	local segCount: number = self.SegCount
	local start: number = self.Cur % segCount + 1
	for k = 0, segCount - 1 do
		local si = (start - 1 + k) % segCount + 1
		local seg: buffer? = self.Segs[si]
		if seg then
			local used: number = self.Used[si]
			local off = 0
			local seq: number = self.FirstSeq[si]
			while off < used do
				local kind = readu8(seg, off)
				local sz = SIZES[kind]
				if not sz then break end
				fn(seq, kind, seg, off)
				off += sz
				seq += 1
			end
		end
	end
end

function EventLog.Decode(kind: number, b: buffer, o: number): { [string]: any }
	local t: { [string]: any } = { kind = kind, ms = readu32(b, o + 1) }
	if kind == 1 then
		t.shape = readu8(b, o + 5)
		t.pos = Vector3.new(readf32(b, o + 6), readf32(b, o + 10), readf32(b, o + 14))
		t.force = readf32(b, o + 18)
		t.look = Vector3.new(readi16(b, o + 22) / 32767, readi16(b, o + 24) / 32767, readi16(b, o + 26) / 32767)
		t.p1, t.p2, t.p3 = readu16(b, o + 28) / 10, readu16(b, o + 30) / 10, readu16(b, o + 32) / 10
	elseif kind == 2 then
		t.count = readu16(b, o + 5)
	elseif kind == 3 then
		t.fid = readu32(b, o + 5)
		t.n = readu16(b, o + 9)
		t.welded = readu8(b, o + 11) == 1
		t.mass = readf32(b, o + 12)
		t.com = Vector3.new(readf32(b, o + 16), readf32(b, o + 20), readf32(b, o + 24))
		t.vel = Vector3.new(readi16(b, o + 28) / 10, readi16(b, o + 30) / 10, readi16(b, o + 32) / 10)
	elseif kind == 4 or kind == 5 then
		t.id = readu32(b, o + 5)
	elseif kind == 6 then
		t.id = readu32(b, o + 5)
		t.pieces = readu8(b, o + 9)
	end
	return t
end

function EventLog:Export(): string
	local parts: { { buffer | number } } = {}
	local total = 0
	local segCount: number = self.SegCount
	local start: number = self.Cur % segCount + 1
	for k = 0, segCount - 1 do
		local si = (start - 1 + k) % segCount + 1
		local seg: buffer? = self.Segs[si]
		if seg and self.Used[si] > 0 then
			parts[#parts + 1] = { seg, self.Used[si] }
			total += self.Used[si]
		end
	end
	local out = bcreate(16 + total)
	writeu32(out, 0, MAGIC)
	writef64(out, 4, self.Base)
	writeu32(out, 12, total)
	local off = 16
	for i = 1, #parts do
		local seg = parts[i][1] :: buffer
		local used = parts[i][2] :: number
		bcopy(out, off, seg, 0, used)
		off += used
	end
	return buffer.tostring(out)
end

function EventLog:Stats(): { [string]: number }
	local bytes = 0
	local segs = 0
	for i = 1, self.SegCount do
		if self.Segs[i] then
			segs += 1
			bytes += blen(self.Segs[i])
		end
	end
	return { AllocatedBytes = bytes, Segments = segs, Events = self.Seq, Dropped = self.Dropped }
end

return EventLog

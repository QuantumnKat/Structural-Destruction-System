--!strict
--!native

local Config = require(script.Parent.InterestConf)
local AOIConf = Config.GetConfig("AOI") :: any

export type Grid = {
	CellSize: number,
	InvCell: number,
	CellCount: number,
	Capacity: number,
	Query: number,
	Head: buffer,
	Next: buffer,
	Prev: buffer,
	CellOf: buffer,
	Stamp: buffer,
}

local AOI = {}

local CullDistSq: number = AOIConf.NetCullDistanceSquared or 1_500_000
local CullDist: number = math.sqrt(CullDistSq)
local LeaveDistSq: number = CullDistSq * (AOIConf.HysteresisMultiplier or 1.21)
local DefaultFreq: number = AOIConf.NetUpdateFrequency or 30
local AlwaysRelevant: boolean = AOIConf.AlwaysRelevant or false
local CheckInterval: number = AOIConf.RelevancyCheckInterval or 0.1
local DefaultCellCount = 2048

local function hash(cx: number, cz: number, count: number): number
	return bit32.bxor(cx * 73856093, cz * 19349663) % count
end

local function unlink(grid: Grid, id: number, cell: number)
	local prev = buffer.readu16(grid.Prev, id * 2)
	local nextId = buffer.readu16(grid.Next, id * 2)

	if prev ~= 0 then
		buffer.writeu16(grid.Next, prev * 2, nextId)
	else
		buffer.writeu16(grid.Head, cell * 2, nextId)
	end

	if nextId ~= 0 then
		buffer.writeu16(grid.Prev, nextId * 2, prev)
	end
end

function AOI.NewGrid(capacity: number, cellSize: number?, cellCount: number?): Grid
	local size = cellSize or math.max(CullDist * 0.5, 32)
	local count = cellCount or DefaultCellCount

	return {
		CellSize = size,
		InvCell = 1 / size,
		CellCount = count,
		Capacity = capacity,
		Query = 0,
		Head = buffer.create(count * 2),
		Next = buffer.create((capacity + 1) * 2),
		Prev = buffer.create((capacity + 1) * 2),
		CellOf = buffer.create((capacity + 1) * 2),
		Stamp = buffer.create((capacity + 1) * 4),
	}
end

function AOI.Update(grid: Grid, id: number, x: number, z: number)
	local cell = hash(math.floor(x * grid.InvCell), math.floor(z * grid.InvCell), grid.CellCount)
	local current = buffer.readu16(grid.CellOf, id * 2)

	if current == cell + 1 then
		return
	end

	if current ~= 0 then
		unlink(grid, id, current - 1)
	end

	local head = buffer.readu16(grid.Head, cell * 2)
	buffer.writeu16(grid.Next, id * 2, head)
	buffer.writeu16(grid.Prev, id * 2, 0)
	if head ~= 0 then
		buffer.writeu16(grid.Prev, head * 2, id)
	end
	buffer.writeu16(grid.Head, cell * 2, id)
	buffer.writeu16(grid.CellOf, id * 2, cell + 1)
end

function AOI.Remove(grid: Grid, id: number)
	local current = buffer.readu16(grid.CellOf, id * 2)
	if current ~= 0 then
		unlink(grid, id, current - 1)
		buffer.writeu16(grid.CellOf, id * 2, 0)
	end
end

function AOI.Query(grid: Grid, x: number, z: number, radius: number, out: buffer): number
	local stampId = grid.Query + 1
	if stampId >= 4294967000 then
		buffer.fill(grid.Stamp, 0, 0)
		stampId = 1
	end
	grid.Query = stampId

	local cx = math.floor(x * grid.InvCell)
	local cz = math.floor(z * grid.InvCell)
	local r = math.ceil(radius * grid.InvCell)
	local count = grid.CellCount
	local n = 0

	for gx = cx - r, cx + r do
		for gz = cz - r, cz + r do
			local id = buffer.readu16(grid.Head, hash(gx, gz, count) * 2)
			while id ~= 0 do
				if buffer.readu32(grid.Stamp, id * 4) ~= stampId then
					buffer.writeu32(grid.Stamp, id * 4, stampId)
					buffer.writeu16(out, n * 2, id)
					n += 1
				end
				id = buffer.readu16(grid.Next, id * 2)
			end
		end
	end

	return n
end

function AOI.InRange(distSq: number): boolean
	if AlwaysRelevant then
		return true
	end
	return distSq < CullDistSq
end

function AOI.InRangeHysteresis(distSq: number, wasVisible: boolean): boolean
	if AlwaysRelevant then
		return true
	end
	return distSq < (if wasVisible then LeaveDistSq else CullDistSq)
end

function AOI.Check(fx: number, fy: number, fz: number, x: number, y: number, z: number): (boolean, number)
	local dx = x - fx
	local dy = y - fy
	local dz = z - fz
	local distSq = dx * dx + dy * dy + dz * dz
	return AOI.InRange(distSq), distSq
end

AOI.CullDistSq = CullDistSq
AOI.CullDist = CullDist
AOI.LeaveDistSq = LeaveDistSq
AOI.DefaultFreq = DefaultFreq
AOI.CheckInterval = CheckInterval
AOI.AlwaysRelevant = AlwaysRelevant

return AOI

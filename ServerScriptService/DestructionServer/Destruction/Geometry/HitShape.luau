--!strict
--!native

local HitShape = {}

export type Shape = {
	Type: string,
	CFrame: CFrame,
	Radius: number?,
	Size: Vector3?,
	Length: number?,
	HalfAngle: number?,
	Centered: boolean?,
	Solid: boolean?,
	Margin: number?,
	Falloff: string?,
	AxialFalloff: number?,
	DirectionMode: string?,
	FixedDirection: Vector3?,
	Pierce: boolean?,
	PierceLoss: number?,
}

export type Hit = {
	idx: number,
	force: number,
	dir: Vector3,
	point: Vector3,
	s: number,
	t: number,
}

local floor = math.floor
local mathmax = math.max
local mathmin = math.min
local mathabs = math.abs
local mathsqrt = math.sqrt
local mathclamp = math.clamp

local CELL_MIN = 8
local MAX_CELLS = 8192
local BIG_NODE_CELLS = 512

local DEFAULT_DIR: { [string]: string } = {
	Sphere = "Radial", Box = "Radial", Capsule = "Axis",
	Cylinder = "Radial", Cone = "Radial", Line = "Axis",
}

local indexCache: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any

local function cellKey(cx: number, cy: number, cz: number): number
	return ((cx + 32768) * 65536 + (cz + 32768)) * 65536 + (cy + 32768)
end

local function buildIndex(graph: any): any
	local cell = mathmax(CELL_MIN, ((graph.Config and graph.Config.BASE_VOXEL_SIZE) or 2) * 4)
	local grid: { [number]: { number } } = {}
	local big: { number } = {}

	for idx, node in pairs(graph.Nodes) do
		local h: Vector3 = node.Size * 0.5
		local p: Vector3 = node.Position
		local x0, x1 = floor((p.X - h.X) / cell), floor((p.X + h.X) / cell)
		local y0, y1 = floor((p.Y - h.Y) / cell), floor((p.Y + h.Y) / cell)
		local z0, z1 = floor((p.Z - h.Z) / cell), floor((p.Z + h.Z) / cell)

		if (x1 - x0 + 1) * (y1 - y0 + 1) * (z1 - z0 + 1) > BIG_NODE_CELLS then
			big[#big + 1] = idx
		else
			for cx = x0, x1 do
				for cy = y0, y1 do
					for cz = z0, z1 do
						local k = cellKey(cx, cy, cz)
						local list = grid[k]
						if not list then
							list = {}
							grid[k] = list
						end
						list[#list + 1] = idx
					end
				end
			end
		end
	end

	local ix = { Cell = cell, Grid = grid, Big = big }
	indexCache[graph] = ix
	return ix
end

function HitShape.Invalidate(graph: any)
	indexCache[graph] = nil
end

------------------------------------------------------------------
-- SHAPE PREPARATION + SDF
------------------------------------------------------------------
local function prepare(shape: Shape): any
	local cf = shape.CFrame
	local pos = cf.Position
	local look = cf.LookVector
	local kind = shape.Type
	local P: any = { Type = kind, CF = cf, Pos = pos, Look = look }

	if kind == "Sphere" then
		local r = mathmax(shape.Radius or 1, 0.05)
		P.R = r
		P.Min = pos - Vector3.new(r, r, r)
		P.Max = pos + Vector3.new(r, r, r)

	elseif kind == "Box" then
		local s = shape.Size or Vector3.new(2, 2, 2)
		local H = Vector3.new(mathmax(s.X * 0.5, 0.05), mathmax(s.Y * 0.5, 0.05), mathmax(s.Z * 0.5, 0.05))
		P.H = H
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local ex = mathabs(r.X) * H.X + mathabs(u.X) * H.Y + mathabs(l.X) * H.Z
		local ey = mathabs(r.Y) * H.X + mathabs(u.Y) * H.Y + mathabs(l.Y) * H.Z
		local ez = mathabs(r.Z) * H.X + mathabs(u.Z) * H.Y + mathabs(l.Z) * H.Z
		P.Min = pos - Vector3.new(ex, ey, ez)
		P.Max = pos + Vector3.new(ex, ey, ez)

	elseif kind == "Capsule" or kind == "Cylinder" or kind == "Line" then
		local len = mathmax(shape.Length or 4, 0.1)
		local r = mathmax(shape.Radius or (if kind == "Line" then 0.25 else 1), 0.05)
		local A = if shape.Centered then pos - look * (len * 0.5) else pos
		local B = A + look * len
		P.R = r
		P.Len = len
		P.A = A
		P.B = B
		P.Ab = B - A
		P.Ab2 = len * len
		P.Min = A:Min(B) - Vector3.new(r, r, r)
		P.Max = A:Max(B) + Vector3.new(r, r, r)

	elseif kind == "Cone" then
		local len = mathmax(shape.Length or 8, 0.1)
		local ang = math.rad(mathclamp(shape.HalfAngle or 30, 1, 89))
		P.Len = len
		P.Tan = math.tan(ang)
		P.Cos = math.cos(ang)
		P.A = pos
		P.B = pos + look * len
		local er = len * P.Tan
		P.Min = pos:Min(P.B) - Vector3.new(er, er, er)
		P.Max = pos:Max(P.B) + Vector3.new(er, er, er)

	else
		error("HitShape: invalid type: " .. tostring(kind))
	end

	if shape.Solid ~= nil then
		P.Solid = shape.Solid
	else
		P.Solid = (kind == "Box")
	end
	return P
end

local function evalShape(P: any, c: Vector3): (number, number, number, number, Vector3)
	local kind = P.Type

	if kind == "Sphere" then
		local m = (c - P.Pos).Magnitude
		return m - P.R, m / P.R, P.R, 0, P.Pos

	elseif kind == "Box" then
		local lp: Vector3 = P.CF:PointToObjectSpace(c)
		local H: Vector3 = P.H
		local ax, ay, az = mathabs(lp.X), mathabs(lp.Y), mathabs(lp.Z)
		local qx, qy, qz = ax - H.X, ay - H.Y, az - H.Z
		local ox, oy, oz = mathmax(qx, 0), mathmax(qy, 0), mathmax(qz, 0)
		local sd = mathsqrt(ox * ox + oy * oy + oz * oz) + mathmin(mathmax(qx, mathmax(qy, qz)), 0)
		local rn = mathmax(ax / H.X, mathmax(ay / H.Y, az / H.Z))
		return sd, rn, mathmin(H.X, mathmin(H.Y, H.Z)), 0, P.Pos

	elseif kind == "Capsule" or kind == "Line" then
		local ab: Vector3 = P.Ab
		local s = mathclamp((c - P.A):Dot(ab) / P.Ab2, 0, 1)
		local closest: Vector3 = P.A + ab * s
		local m = (c - closest).Magnitude
		return m - P.R, m / P.R, P.R, s * P.Len, closest

	elseif kind == "Cylinder" then
		local axis: Vector3 = P.Look
		local ac = c - P.A
		local s = ac:Dot(axis)
		local rm = (ac - axis * s).Magnitude
		local dRad = rm - P.R
		local dAx = mathmax(-s, s - P.Len)
		local sd: number
		if dRad > 0 and dAx > 0 then
			sd = mathsqrt(dRad * dRad + dAx * dAx)
		else
			sd = mathmax(dRad, dAx)
		end
		local sc = mathclamp(s, 0, P.Len)
		return sd, rm / P.R, P.R, sc, P.A + axis * sc

	else -- Cone
		local axis: Vector3 = P.Look
		local ac = c - P.A
		local s = ac:Dot(axis)
		local rm = (ac - axis * s).Magnitude
		local rs = mathmax(s, 0) * P.Tan
		local sd = (rm - rs) * P.Cos
		if s < 0 then sd = mathmax(sd, -s) end
		if s > P.Len then sd = mathmax(sd, s - P.Len) end
		local rchar = mathmax(rs, 0.5)
		local sc = mathclamp(s, 0, P.Len)
		return sd, rm / rchar, rchar, sc, P.A + axis * sc
	end
end

local function applyFalloff(mode: string, t: number): number
	if mode == "None" then
		return 1
	elseif mode == "Quadratic" then
		return t * t
	elseif mode == "Smooth" then
		return t * t * (3 - 2 * t)
	end
	return t
end

------------------------------------------------------------------
-- PUBLIC
------------------------------------------------------------------
function HitShape.BoundingRadius(shape: Shape): number
	local P = prepare(shape)
	return ((P.Max :: Vector3) - (P.Min :: Vector3)).Magnitude * 0.5
end

function HitShape.Query(graph: any, shape: Shape, force: number): { Hit }
	local P = prepare(shape)
	local nodes = graph.Nodes
	local ix = indexCache[graph] or buildIndex(graph)
	local cell: number = ix.Cell
	local mn: Vector3, mx: Vector3 = P.Min, P.Max

	local x0, x1 = floor(mn.X / cell), floor(mx.X / cell)
	local y0, y1 = floor(mn.Y / cell), floor(mx.Y / cell)
	local z0, z1 = floor(mn.Z / cell), floor(mx.Z / cell)

	local candidates: { number } = {}
	if (x1 - x0 + 1) * (y1 - y0 + 1) * (z1 - z0 + 1) > MAX_CELLS then
		for idx in pairs(nodes) do
			candidates[#candidates + 1] = idx
		end
	else
		local seen: { [number]: boolean } = {}
		local grid = ix.Grid
		for cx = x0, x1 do
			for cy = y0, y1 do
				for cz = z0, z1 do
					local list = grid[cellKey(cx, cy, cz)]
					if list then
						for i = 1, #list do
							local idx = list[i]
							if not seen[idx] then
								seen[idx] = true
								candidates[#candidates + 1] = idx
							end
						end
					end
				end
			end
		end
		local big = ix.Big
		for i = 1, #big do
			local idx = big[i]
			if not seen[idx] then
				seen[idx] = true
				candidates[#candidates + 1] = idx
			end
		end
	end

	local kind = shape.Type
	local falloffMode = shape.Falloff or "Smooth"
	local axialFalloff = shape.AxialFalloff or (if kind == "Cone" then 0.5 else 0)
	local margin = shape.Margin or 1.0
	local dirMode = shape.DirectionMode or DEFAULT_DIR[kind] or "Radial"
	local fixed: Vector3? = nil
	if shape.FixedDirection and shape.FixedDirection.Magnitude > 1e-4 then
		fixed = shape.FixedDirection.Unit
	end
	if dirMode == "Fixed" and not fixed then dirMode = "Radial" end

	local solid: boolean = P.Solid
	local len: number? = P.Len
	local look: Vector3 = P.Look
	local hits: { Hit } = {}

	for i = 1, #candidates do
		local node = nodes[candidates[i]]
		if not node or not node.IsActive or node.IsAnchor then continue end

		local c: Vector3 = node.Position
		local hs: Vector3 = node.Size * 0.5
		local nodeR = (hs.X + hs.Y + hs.Z) / 3

		local sd, rn, rchar, s, point = evalShape(P, c)
		if sd > nodeR then continue end

		local t: number
		if solid then
			t = 1 - mathmax(sd, 0) / (nodeR + margin)
		else
			t = 1 - rn / (1 + nodeR / rchar)
		end
		if t <= 0.001 then continue end
		if t > 1 then t = 1 end

		local f = applyFalloff(falloffMode, t)
		if axialFalloff > 0 and len and len > 0 then
			f *= 1 - axialFalloff * mathclamp(s / len, 0, 1)
		end
		local nf = force * f
		if nf <= 0 then continue end

		local dir: Vector3
		if dirMode == "Axis" then
			dir = look
		elseif dirMode == "Fixed" and fixed then
			dir = fixed
		else
			local ref: Vector3 = if kind == "Cone" then P.Pos else point
			local d = c - ref
			local m = d.Magnitude
			dir = if m > 1e-3 then d / m else look
		end

		hits[#hits + 1] = { idx = node.Index or candidates[i], force = nf, dir = dir, point = point, s = s, t = t }
	end

	local pierce = shape.Pierce
	if pierce == nil then pierce = (kind == "Line") end
	if pierce and len and #hits > 0 and force > 0 then
		table.sort(hits, function(a, b) return a.s < b.s end)
		local remaining = force
		local loss = shape.PierceLoss or 1.0
		local dead = false
		for i = 1, #hits do
			local h = hits[i]
			if dead then
				h.force = 0
			else
				local scale = remaining / force
				if scale <= 0.02 then
					h.force = 0
					dead = true
				else
					h.force *= scale
					local n = nodes[h.idx]
					local hp = (n and n.HP) or 100
					remaining -= mathmin(h.force, hp) * loss
				end
			end
		end
	end

	local out: { Hit } = {}
	for i = 1, #hits do
		if hits[i].force > 0 then
			out[#out + 1] = hits[i]
		end
	end
	table.sort(out, function(a, b) return a.force > b.force end)
	return out
end

function HitShape.QueryParts(shape: Shape, items: { any }, force: number): { any }
	local P = prepare(shape)
	local kind = shape.Type
	local falloffMode = shape.Falloff or "Smooth"
	local axialFalloff = shape.AxialFalloff or (if kind == "Cone" then 0.5 else 0)
	local margin = shape.Margin or 1.0
	local dirMode = shape.DirectionMode or DEFAULT_DIR[kind] or "Radial"
	local fixed: Vector3? = nil
	if shape.FixedDirection and shape.FixedDirection.Magnitude > 1e-4 then
		fixed = shape.FixedDirection.Unit
	end
	if dirMode == "Fixed" and not fixed then dirMode = "Radial" end

	local solid: boolean = P.Solid
	local len: number? = P.Len
	local look: Vector3 = P.Look
	local out: { any } = {}

	for i = 1, #items do
		local it = items[i]
		local c: Vector3 = it.pos
		local hs: Vector3 = it.half
		local nodeR = (hs.X + hs.Y + hs.Z) / 3

		local sd, rn, rchar, s, point = evalShape(P, c)
		if sd > nodeR then continue end

		local t: number
		if solid then
			t = 1 - mathmax(sd, 0) / (nodeR + margin)
		else
			t = 1 - rn / (1 + nodeR / rchar)
		end
		if t <= 0.001 then continue end
		if t > 1 then t = 1 end

		local f = applyFalloff(falloffMode, t)
		if axialFalloff > 0 and len and len > 0 then
			f *= 1 - axialFalloff * mathclamp(s / len, 0, 1)
		end
		local nf = force * f
		if nf <= 0 then continue end

		local dir: Vector3
		if dirMode == "Axis" then
			dir = look
		elseif dirMode == "Fixed" and fixed then
			dir = fixed
		else
			local ref: Vector3 = if kind == "Cone" then P.Pos else point
			local d = c - ref
			local m = d.Magnitude
			dir = if m > 1e-3 then d / m else look
		end

		out[#out + 1] = { ref = it.ref, force = nf, dir = dir, point = point, t = t }
	end

	table.sort(out, function(a, b) return a.force > b.force end)
	return out
end

return HitShape

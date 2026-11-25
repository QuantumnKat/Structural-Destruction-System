--!strict
--!native

local Shapes: any = {}

local VALID_TYPES = { Sphere = true, Box = true, Capsule = true, Cylinder = true, Cone = true, Line = true }

local function sanitizeShape(spec: any): (any?, string?)
	if typeof(spec) ~= "table" or type(spec.Type) ~= "string" or not VALID_TYPES[spec.Type] then
		return nil, "invalid Type"
	end
	if typeof(spec.CFrame) ~= "CFrame" then return nil, "invalid CFrame" end

	local out: any = { Type = spec.Type, CFrame = spec.CFrame }
	for _, k in ipairs({ "Radius", "Length", "HalfAngle", "Margin", "AxialFalloff", "PierceLoss" }) do
		if type(spec[k]) == "number" and spec[k] == spec[k] then out[k] = math.clamp(spec[k], 0, 500) end
	end
	if typeof(spec.Size) == "Vector3" then out.Size = spec.Size end
	if typeof(spec.FixedDirection) == "Vector3" then out.FixedDirection = spec.FixedDirection end
	for _, k in ipairs({ "Centered", "Solid", "Pierce" }) do
		if type(spec[k]) == "boolean" then out[k] = spec[k] end
	end
	for _, k in ipairs({ "Falloff", "DirectionMode" }) do
		if type(spec[k]) == "string" then out[k] = spec[k] end
	end
	return out, nil
end

function Shapes.Init(ctx: any, Debug: any)
	local State, Mods, Remote = ctx.State, ctx.Mods, ctx.Remote
	local Handler = Mods.Handler
	local R = Debug.Register

	local function drawIf(shape: any)
		if ctx.Config.Debug.DrawOnHit then Debug.Draw.Shape(shape) end
	end

	local function need(): (any?, string?)
		if not State.graph then return nil, "no graph" end
		return Handler, nil
	end

	R("explode", function(_, pos: any, radius: any, force: any)
		local h, err = need()
		if not h then return err end
		if typeof(pos) ~= "Vector3" then return "invalid pos" end
		local r, f = tonumber(radius) or 12, tonumber(force) or 5000
		drawIf({ Type = "Sphere", CFrame = CFrame.new(pos), Radius = r })
		local ok, res = pcall(h.Explode, State.graph, pos, r, f, Remote.Event, State.ActiveParts, nil)
		State.MarkDirty()
		if not ok then return "ERROR: " .. tostring(res) end
		return ("Explode @ (%0.1f,%0.1f,%0.1f) r=%0.1f f=%0.1f => %s"):format(pos.X, pos.Y, pos.Z, r, f, tostring(res))
	end)

	R("ray", function(_, a: any, b: any, radius: any, force: any)
		local h, err = need()
		if not h then return err end
		if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then return "invalid pos" end
		local r = tonumber(radius) or 0.4
		drawIf({ Type = "Line", CFrame = CFrame.lookAt(a, b), Length = (b - a).Magnitude, Radius = r })
		local ok, res = pcall(h.BreakLine, State.graph, a, b, r, tonumber(force) or 4000, Remote.Event, State.ActiveParts, nil)
		State.MarkDirty()
		if not ok then return "ERROR: " .. tostring(res) end
		return ("Ray %s -> %s => %s"):format(tostring(a), tostring(b), tostring(res))
	end)

	R("slash", function(_, a: any, b: any, radius: any, force: any)
		local h, err = need()
		if not h then return err end
		if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then return "invalid pos" end
		local r = tonumber(radius) or 1.5
		drawIf({ Type = "Capsule", CFrame = CFrame.lookAt(a, b), Length = (b - a).Magnitude, Radius = r })
		local ok, res = pcall(h.BreakCapsule, State.graph, a, b, r, tonumber(force) or 4000, Remote.Event, State.ActiveParts, nil)
		State.MarkDirty()
		if not ok then return "ERROR: " .. tostring(res) end
		return ("Slash %s -> %s => %s"):format(tostring(a), tostring(b), tostring(res))
	end)

	R("cone", function(_, origin: any, direction: any, length: any, halfAngle: any, force: any)
		local h, err = need()
		if not h then return err end
		if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" or direction.Magnitude < 1e-3 then
			return "invalid origin/direction"
		end
		local len, ang = tonumber(length) or 20, tonumber(halfAngle) or 30
		drawIf({ Type = "Cone", CFrame = CFrame.lookAt(origin, origin + direction.Unit), Length = len, HalfAngle = ang })
		local ok, res = pcall(h.BreakCone, State.graph, origin, direction, len, ang, tonumber(force) or 3000, Remote.Event, State.ActiveParts, nil)
		State.MarkDirty()
		if not ok then return "ERROR: " .. tostring(res) end
		return ("Cone => %s"):format(tostring(res))
	end)

	R("box_from_part", function(_, idx: any, force: any)
		local h, err = need()
		if not h then return err end
		if type(idx) ~= "number" then return "invalid idx" end
		local part = State.GetPartMap(true)[idx]
		if not part or not part.Parent then return "no part at idx " .. idx end
		local shape = {
			Type = "Box", CFrame = part.CFrame, Size = part.Size, Solid = true,
			Margin = 1.0, Falloff = "Smooth", DirectionMode = "Radial",
		}
		drawIf(shape)
		local ok, res = pcall(h.BreakByShape, State.graph, shape, tonumber(force) or 4000, Remote.Event, State.ActiveParts,
			{ ForceMultiplier = 1.0, ExcludeIdx = { [idx] = true } })
		State.MarkDirty()
		if not ok then return "ERROR: " .. tostring(res) end
		return ("BoxFromPart idx=%d => %s"):format(idx, tostring(res))
	end)

	R("hit_shape_from_part", function(_, idx: any, force: any, excludeSelf: any)
		local h, err = need()
		if not h then return err end
		if type(idx) ~= "number" then return "invalid idx" end
		local part = State.GetPartMap(true)[idx]
		if not part or not part.Parent then return "no part at idx " .. idx end
		local shape = h.ShapeFromPart(part, part.Position)
		drawIf(shape)
		local o: any = { ForceMultiplier = 1.0 }
		if excludeSelf ~= false then o.ExcludeIdx = { [idx] = true } end
		local ok, res = pcall(h.BreakByShape, State.graph, shape, tonumber(force) or 4000, Remote.Event, State.ActiveParts, o)
		State.MarkDirty()
		if not ok then return "ERROR: " .. tostring(res) end
		return ("HitShapeFromPart idx=%d => %s"):format(idx, tostring(res))
	end)

	R("shape", function(_, spec: any, force: any, opts: any)
		local h, err = need()
		if not h then return err end
		local shape, e2 = sanitizeShape(spec)
		if not shape then return "ERROR: " .. tostring(e2) end
		drawIf(shape)
		local o: any = nil
		if typeof(opts) == "table" then
			o = { ForceMultiplier = tonumber(opts.ForceMultiplier) or 3.0, Secondary = opts.Secondary == true }
		end
		local ok, res = pcall(h.BreakByShape, State.graph, shape, tonumber(force) or 4000, Remote.Event, State.ActiveParts, o)
		State.MarkDirty()
		if not ok then return "ERROR: " .. tostring(res) end
		return tostring(res)
	end)

	R("draw_shape", function(_, spec: any)
		local shape, e2 = sanitizeShape(spec)
		if not shape then return "ERROR: " .. tostring(e2) end
		Debug.Draw.Shape(shape)
		return "drawn"
	end)

	R("preview_hits", function(_, spec: any, force: any)
		if not State.graph then return "no graph" end
		local shape, e2 = sanitizeShape(spec)
		if not shape then return "ERROR: " .. tostring(e2) end
		local f = tonumber(force) or 4000
		local hits = Mods.HitShape.Query(State.graph, shape, f)
		Debug.Draw.Shape(shape)
		Debug.Draw.Hits(State.graph, hits)
		local top = {}
		for i = 1, math.min(#hits, 10) do
			top[i] = { idx = hits[i].idx, force = math.floor(hits[i].force), t = math.floor(hits[i].t * 100) / 100 }
		end
		return { hits = #hits, top = top }
	end)
end

return Shapes

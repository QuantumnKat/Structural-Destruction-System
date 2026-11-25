--!strict
--!native

local Validation = {}

function Validation.finite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function Validation.vector(value: any): boolean
	return typeof(value) == "Vector3" and Validation.finite(value.X) and Validation.finite(value.Y) and Validation.finite(value.Z)
end

function Validation.validate(action: any, data: any): (boolean, string?)
	if type(data) ~= "table" or getmetatable(data) ~= nil then return false, "InvalidPayload" end
	local allowed = if action == "HIT_REQUEST" then { idx = true, force = true }
		elseif action == "BREAK_AT_POSITION" then { idx = true, pos = true, radius = true } else nil
	if not allowed then return false, "UnknownAction" end
	local count = 0
	for key in data do
		count += 1
		if count > 3 or not allowed[key] then return false, "UnexpectedField" end
	end
	if not Validation.finite(data.idx) or data.idx % 1 ~= 0 or data.idx < 1 or data.idx > 4294967295 then
		return false, "InvalidIndex"
	end
	if action == "HIT_REQUEST" then
		if not Validation.finite(data.force) or data.force < 0 then return false, "InvalidForce" end
	else
		if not Validation.vector(data.pos) then return false, "InvalidPosition" end
		if data.radius ~= nil and (not Validation.finite(data.radius) or data.radius <= 0) then return false, "InvalidRadius" end
	end
	return true
end

function Validation.intersectsNode(position: Vector3, radius: number, node: any): boolean
	if not Validation.vector(node.Position) or not Validation.vector(node.Size) then return false end
	local bound = node.Size.Magnitude * 0.5 + radius
	return (position - node.Position).Magnitude <= bound
end

return table.freeze(Validation)
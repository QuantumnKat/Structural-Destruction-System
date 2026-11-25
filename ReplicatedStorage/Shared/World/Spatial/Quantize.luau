--!strict

local Quantize = {}
local POS_SCALE = 1 / 0.05 
local VEL_SCALE = 1 / 1.0

function Quantize.Vector3ToInt16(v: Vector3): (number, number, number)
	if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then return 0, 0, 0 end
	return math.clamp(math.round(v.X * POS_SCALE), -32768, 32767),
		math.clamp(math.round(v.Y * POS_SCALE), -32768, 32767),
		math.clamp(math.round(v.Z * POS_SCALE), -32768, 32767)
end

function Quantize.Int16ToVector3(x: number, y: number, z: number): Vector3
	return Vector3.new(x * 0.05, y * 0.05, z * 0.05)
end

function Quantize.VelocityToInt16(v: Vector3): (number, number, number)
	if v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z then return 0, 0, 0 end
	return math.clamp(math.round(v.X * VEL_SCALE), -32768, 32767),
		math.clamp(math.round(v.Y * VEL_SCALE), -32768, 32767),
		math.clamp(math.round(v.Z * VEL_SCALE), -32768, 32767)
end

function Quantize.Int16ToVelocity(x: number, y: number, z: number): Vector3
	return Vector3.new(x * 1.0, y * 1.0, z * 1.0)
end

function Quantize.CFrameToInt16(cf: CFrame): (number, number, number, number, number, number)
	local x, y, z = Quantize.Vector3ToInt16(cf.Position)
	local rx, ry, rz = cf:ToOrientation()

	if rx ~= rx then rx = 0 end
	if ry ~= ry then ry = 0 end
	if rz ~= rz then rz = 0 end

	return x, y, z, 
		math.clamp(math.round(math.deg(rx)), -32768, 32767),
		math.clamp(math.round(math.deg(ry)), -32768, 32767),
		math.clamp(math.round(math.deg(rz)), -32768, 32767)
end

function Quantize.Int16ToCFrame(qx: number, qy: number, qz: number, qrx: number, qry: number, qrz: number): CFrame
	local pos = Quantize.Int16ToVector3(qx, qy, qz)
	local rot = CFrame.fromOrientation(math.rad(qrx), math.rad(qry), math.rad(qrz))
	return CFrame.new(pos) * rot
end

return Quantize

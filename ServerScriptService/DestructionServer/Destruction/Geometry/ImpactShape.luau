--!strict
-- EditorSync: refactor-v1

local function shapeFromPart(part: BasePart?, fallbackPos: Vector3): any
	if not part or not part.Parent then
		return { Type = "Sphere", CFrame = CFrame.new(fallbackPos), Radius = 3, Falloff = "Smooth" }
	end
	local p: any = part
	local size: Vector3 = part.Size
	local cf: CFrame = part.CFrame

	if part:IsA("Part") then
		if p.Shape == Enum.PartType.Ball then
			return {
				Type = "Sphere", CFrame = cf, Radius = math.max(size.X, size.Y, size.Z) * 0.5,
				Solid = true, Falloff = "Smooth",
			}
		elseif p.Shape == Enum.PartType.Cylinder then
			return {
				Type = "Cylinder",
				CFrame = CFrame.lookAt(cf.Position, cf.Position + cf.RightVector),
				Length = size.X, Radius = math.min(size.Y, size.Z) * 0.5,
				Centered = true, Solid = true, Falloff = "Smooth",
			}
		end
	end
	return { Type = "Box", CFrame = cf, Size = size, Solid = true, Margin = 1.0, Falloff = "Smooth" }
end

return shapeFromPart

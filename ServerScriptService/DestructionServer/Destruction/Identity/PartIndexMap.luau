--!strict

local PartIndexMap = {}

function PartIndexMap.Build(root: Instance): { [number]: BasePart }
	local out: { [number]: BasePart } = {}
	if not root then return out end
	local descendants = root:GetDescendants()
	for i = 1, #descendants do
		local d = descendants[i]
		if d:IsA("BasePart") then
			local idx = d:GetAttribute("PartIndex")
			if type(idx) == "number" then
				out[idx] = d
			end
		end
	end
	return out
end

return PartIndexMap

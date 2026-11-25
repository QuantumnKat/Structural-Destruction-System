--!strict
return function(player: Player): BasePart?
	local character = player.Character
	if not character or not character:IsDescendantOf(workspace) then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

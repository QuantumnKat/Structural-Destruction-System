--!strict
--!native

-- Init before any :Connect; clients may fire as soon as they join.

local Remote: any = {}

function Remote.GetOrCreate(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	if existing then existing:Destroy() end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

function Remote.Init(ctx: any)
	Remote.Event = Remote.GetOrCreate(ctx.Services.ReplicatedStorage, "RemoteEvent", ctx.Config.Remote.Event) :: RemoteEvent
	ctx.Log.Info("Boot", "%s ready", ctx.Config.Remote.Event)
end

return Remote

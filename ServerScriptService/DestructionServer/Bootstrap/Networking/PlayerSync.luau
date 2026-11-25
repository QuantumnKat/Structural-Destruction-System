--!strict
--!native

local PlayerSync = {}

function PlayerSync.Init(ctx: any)
	local handshake = require(ctx.ServerFolder.Replication.ServerHandshake)
	handshake.OnClientReady(function(player: Player)
		local deadline = os.clock() + ctx.Config.Join.MaxWaitReady
		while player.Parent and not ctx.State.IsReady() and os.clock() < deadline do
			task.wait(0.25)
		end
		if player.Parent and ctx.State.IsReady() then
			ctx.MapService.SendTo(player)
		end
	end)
	handshake.OnMapLoaded(function(player: Player)
		if player.Parent and ctx.State.IsReady() then
			ctx.Mods.FragmentManager.SendSnapshot(player)
		end
	end)
	ctx.Mods.ServerReplication.UseGate(handshake.IsLoaded)
	handshake.Init(ctx.Remote.Event)
end

return PlayerSync

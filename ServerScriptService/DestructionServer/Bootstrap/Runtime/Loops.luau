--!strict
--!native

local Loops: any = {}

local stats = {
	repMs = 0.0,
	stabMs = 0.0,
	stabErrors = 0,
	bytesTotal = 0,
	packetsTotal = 0,
	bytesPerSec = 0.0,
	packetsPerSec = 0.0,
}
local winBytes, winPackets, winT = 0, 0, 0.0

function Loops.GetStats(): { [string]: number }
	return table.clone(stats)
end

function Loops.Init(ctx: any)
	local State, Remote, Log, Handler = ctx.State, ctx.Remote, ctx.Log, ctx.Mods.Handler
	local RunService = ctx.Services.RunService
	local Workspace = ctx.Services.Workspace

	RunService.Heartbeat:Connect(function(dt: number)
		if not State.graph then return end

		local t0 = os.clock()
		local payloads = State.replication:Step(dt, State.ActiveParts)
		for player, buf in pairs(payloads) do
			Remote.Event:FireClient(player, "DYNAMIC_REPLICATE", buf)
			local len = buffer.len(buf)
			winBytes += len
			winPackets += 1
			stats.bytesTotal += len
			stats.packetsTotal += 1
		end
		stats.repMs += ((os.clock() - t0) * 1000 - stats.repMs) * 0.05

		winT += dt
		if winT >= 1 then
			stats.bytesPerSec = winBytes / winT
			stats.packetsPerSec = winPackets / winT
			winBytes, winPackets, winT = 0, 0, 0.0
			Log.Print("Replication", "%.1f KB/s, %.0f pkt/s, step %.2f ms, active=%d",
				stats.bytesPerSec / 1024, stats.packetsPerSec, stats.repMs, #State.ActiveParts)
		end
	end)

	local cfg = ctx.Config.Stability
	if not cfg.Enabled then return end

	task.spawn(function()
		while true do
			task.wait(cfg.Interval)
			if State.graph then
				local cam = Workspace:FindFirstChild("Camera") or Workspace
				local t0 = os.clock()
				local ok, err = pcall(
					Handler.CheckStability,
					State.graph, State.GetPartMap(), cam, State.ActiveParts, Remote.Event
				)
				stats.stabMs += ((os.clock() - t0) * 1000 - stats.stabMs) * 0.1
				if not ok then
					stats.stabErrors += 1
					Log.Warn("Boot", "CheckStability ERROR: %s", tostring(err))
				end
			end
		end
	end)
end

return Loops

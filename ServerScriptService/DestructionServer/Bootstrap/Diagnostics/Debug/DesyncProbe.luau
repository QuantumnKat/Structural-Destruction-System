--!strict
--!native

local Probe: any = {}

local ctx: any = nil
local pending: { [number]: any } = {}
local counter = 0

local function sane(data: any, n: number): boolean
	if typeof(data) ~= "table" or typeof(data.token) ~= "number" then return false end
	if typeof(data.found) ~= "table" or typeof(data.pos) ~= "table" then return false end
	if #data.found > n or #data.pos > n then return false end
	for i = 1, #data.pos do
		if typeof(data.pos[i]) ~= "Vector3" then return false end
	end
	return true
end

function Probe.OnReply(player: Player, data: any)
	if typeof(data) ~= "table" then return end
	local entry = pending[data.token]
	if not entry or entry.player ~= player or entry.done then return end
	if not sane(data, #entry.ids) then return end
	entry.reply = data
	entry.done = true
end

function Probe.Run(player: Player, sampleCount: any): any
	local State, Log = ctx.State, ctx.Log
	local cfg = ctx.Config.Debug

	local cand: { BasePart } = {}
	for _, p in ipairs(State.ActiveParts) do
		if p and p.Parent and type(p:GetAttribute("ObjectId")) == "number" then
			cand[#cand + 1] = p
		end
	end
	if #cand == 0 then return { error = "no dynamic parts to probe" } end

	local n = math.min(if type(sampleCount) == "number" then sampleCount else cfg.ProbeSample, #cand)
	for i = 1, n do
		local j = math.random(i, #cand)
		cand[i], cand[j] = cand[j], cand[i]
	end

	local ids: { number } = {}
	local spos: { Vector3 } = {}
	local sleeping: { boolean } = {}
	for i = 1, n do
		ids[i] = cand[i]:GetAttribute("ObjectId") :: number
		spos[i] = cand[i].Position
		sleeping[i] = cand[i]:GetAttribute("IsSleeping") == true
	end

	counter += 1
	local token = counter
	local entry: any = { player = player, ids = ids, done = false }
	pending[token] = entry
	ctx.Remote.Event:FireClient(player, "DEBUG_PROBE", { token = token, ids = ids })

	local t0 = os.clock()
	while not entry.done and os.clock() - t0 < cfg.ProbeTimeout do
		task.wait(0.05)
	end
	pending[token] = nil
	if not entry.done then
		return { error = "timeout: client did not reply (is ClientDestructionHandler.Setup connected?)" }
	end

	local reply = entry.reply
	local missing: { any } = {}
	local drifted: { any } = {}
	local sumErr, maxErr, compared = 0.0, 0.0, 0
	local driftSleeping = 0
	for i = 1, n do
		if reply.found[i] == true then
			local err = ((reply.pos[i] :: Vector3) - spos[i]).Magnitude
			compared += 1
			sumErr += err
			if err > maxErr then maxErr = err end
			if err > cfg.ProbeDriftStuds then
				if sleeping[i] then driftSleeping += 1 end
				if #drifted < 10 then
					drifted[#drifted + 1] = { id = ids[i], err = math.floor(err * 10) / 10, serverSleeping = sleeping[i], server = spos[i], client = reply.pos[i] }
				end
			end
		elseif #missing < 10 then
			missing[#missing + 1] = { id = ids[i], serverSleeping = sleeping[i], server = spos[i] }
		end
	end

	local missingCount = n - compared
	local driftCount = 0
	for i = 1, n do
		if reply.found[i] == true and ((reply.pos[i] :: Vector3) - spos[i]).Magnitude > cfg.ProbeDriftStuds then
			driftCount += 1
		end
	end

	local result = {
		sampled = n, serverActive = #State.ActiveParts, client = reply.stats,
		missingOnClient = missingCount, drifted = driftCount, driftedWhileServerSleeping = driftSleeping,
		meanError = if compared > 0 then sumErr / compared else 0, maxError = maxErr,
		missingSamples = missing, driftSamples = drifted,
	}
	Log.Print("Debug", "probe %s: sampled=%d missing=%d drifted=%d meanErr=%.2f maxErr=%.2f",
		player.Name, n, missingCount, driftCount, result.meanError, maxErr)
	return result
end

function Probe.Init(c: any)
	ctx = c
	ctx.Debug.Register("probe_client", function(player: Player, sample: any)
		return Probe.Run(player, sample)
	end)
end

return Probe

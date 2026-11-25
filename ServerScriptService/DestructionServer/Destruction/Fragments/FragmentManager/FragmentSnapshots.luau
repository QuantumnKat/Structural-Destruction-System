--!strict
-- EditorSync: refactor-v1
--!native
return function(deps: any)
local S, Conf = deps.State, deps.Config
local SnapshotCodec, Quantize, PartIds = deps.SnapshotCodec, deps.Quantize, deps.PartIds
local osclock = os.clock
local FragmentManager = {}
local DESTROY_REASONS: { [string]: boolean } = { Shatter = true, Hit = true, Chunk = true }

function FragmentManager.CaptureSnapshot(): buffer?
	if not S.inited or Conf.Snapshot.Enabled == false then return nil end
	local sc = Conf.Snapshot
	local state: buffer = S.state

	if sc.ScanGraphOnCapture then
		for idx, node in pairs(S.graph.Nodes) do
			if not node.IsActive and DESTROY_REASONS[node.DeactivatedBy or ""] and idx <= S.maxIdx then
				if SnapshotCodec.GetState(state, idx) < 2 then
					SnapshotCodec.SetState(state, idx, 2)
				end
			end
		end
	end

	local rle = SnapshotCodec.RleEncode(state)

	local poseCount = 0
	local poseBuf: buffer? = nil
	if sc.IncludePoses then
		local picks: { BasePart } = {}
		local active: { BasePart } = S.active
		for i = 1, #active do
			if #picks >= sc.MaxPoseRecords then break end
			local p = active[i]
			if p and p.Parent and p:GetAttribute("IsSleeping") == true then
				local pid = p:GetAttribute("PartIndex")
				if type(pid) == "number" and pid <= S.maxIdx and SnapshotCodec.GetState(state, pid) == 3 then
					picks[#picks + 1] = p
				end
			end
		end
		poseCount = #picks
		if poseCount > 0 then
			local pb = buffer.create(poseCount * 16)
			for i = 1, poseCount do
				local p = picks[i]
				local o = (i - 1) * 16
				buffer.writeu32(pb, o, p:GetAttribute("PartIndex") :: number)
				local qx, qy, qz, qrx, qry, qrz = Quantize.CFrameToInt16(p.CFrame)
				buffer.writei16(pb, o + 4, qx)
				buffer.writei16(pb, o + 6, qy)
				buffer.writei16(pb, o + 8, qz)
				buffer.writei16(pb, o + 10, qrx)
				buffer.writei16(pb, o + 12, qry)
				buffer.writei16(pb, o + 14, qrz)
			end
			poseBuf = pb
		end
	end

	local seq: number = if S.log then S.log.Seq else 0
	local packed = SnapshotCodec.Pack(S.maxIdx, seq, rle, poseBuf, poseCount)

	local snaps: { any } = S.snapshots
	snaps[#snaps + 1] = { time = osclock(), seq = seq, data = packed }
	while #snaps > sc.MaxSnapshots do
		table.remove(snaps, 1)
	end
	S.dirty = 0
	S.lastSnap = osclock()
	return packed
end

function FragmentManager.GetSnapshot(): buffer?
	local snaps: { any } = S.snapshots
	if #snaps == 0 then return nil end
	return snaps[#snaps].data
end

function FragmentManager.SendSnapshot(player: Player)
	if not S.inited or not S.event then return end
	local data = FragmentManager.CaptureSnapshot() or FragmentManager.GetSnapshot()
	if data then
		S.event:FireClient(player, "SNAPSHOT_STATE", data)
	end
	PartIds.SendAll(player)
end

return FragmentManager
end

--!strict
--!native
local Quantize = require(game:GetService("ReplicatedStorage").Shared.World.Spatial.Quantize)
local Cache = {}
local PACKET_BYTES = 16
local SLEEP_FLAG = 2147483648
local osclock = os.clock
local writeu32 = buffer.writeu32
local writei16 = buffer.writei16
function Cache.Cleanup(self: any, activeParts: { BasePart })
	local validIds: { [number]: boolean } = {}
	for i = 1, #activeParts do
		local p = activeParts[i]
		if p and p.Parent then
			local oid = p:GetAttribute("ObjectId")
			if type(oid) == "number" then
				validIds[oid] = true
			end
		end
	end
	local born = self._born
	for id in pairs(born) do
		if not validIds[id] then
			born[id] = nil
		end
	end
	for _, st in pairs(self.clients) do
		local last, sleepSent = st.Last, st.SleepSent
		for id in pairs(last) do
			if not validIds[id] then last[id] = nil end
		end
		for id in pairs(sleepSent) do
			if not validIds[id] then sleepSent[id] = nil end
		end
	end
end

function Cache.Prepare(self: any, i: number, part: BasePart?, tick: number): boolean
	local stamps = self._stamp
	if stamps[i] == tick then
		return self._valid[i]
	end
	stamps[i] = tick

	local valid = false
	if part and part.Parent and part:IsA("BasePart") then
		local oid = part:GetAttribute("ObjectId")
		if self._partIds then
			oid = self._partIds.Touch(part, oid)
		end
		if type(oid) == "number" and oid < SLEEP_FLAG then
			local born = self._born
			if born[oid] == nil then
				born[oid] = osclock()
			end
			local cf = part.CFrame
			local sleeping = part:GetAttribute("IsSleeping") == true
			local qx, qy, qz, qrx, qry, qrz = Quantize.CFrameToInt16(cf)

			local scratch: buffer = self._scratch
			local base = (i - 1) * PACKET_BYTES
			writeu32(scratch, base, if sleeping then oid + SLEEP_FLAG else oid)
			writei16(scratch, base + 4, qx)
			writei16(scratch, base + 6, qy)
			writei16(scratch, base + 8, qz)
			writei16(scratch, base + 10, qrx)
			writei16(scratch, base + 12, qry)
			writei16(scratch, base + 14, qrz)

			self._id[i] = oid
			self._pos[i] = cf.Position
			self._sleep[i] = sleeping
			valid = true
		end
	end
	self._valid[i] = valid
	return valid
end

return Cache

--!strict
--!native

local writeu32 = buffer.writeu32
local writef32 = buffer.writef32
local readu32  = buffer.readu32
local readf32  = buffer.readf32
local bcreate  = buffer.create
local ins      = table.insert
local mathmax  = math.max

local CollideCheck = {}
CollideCheck.__index = CollideCheck

local function encodeCollidePayload(partIds: { number }, force: number, position: Vector3): buffer
	local n = #partIds
	local buf = bcreate(20 + n * 4)
	local off = 0

	writeu32(buf, off, n); off = off + 4
	writef32(buf, off, force); off = off + 4
	writef32(buf, off, position.X); off = off + 4
	writef32(buf, off, position.Y); off = off + 4
	writef32(buf, off, position.Z); off = off + 4

	for i = 1, n do
		writeu32(buf, off, partIds[i]); off = off + 4
	end

	return buf
end

local function decodeCollidePayload(buf: buffer): ({ number }, number, Vector3)
	local off = 0
	local n = readu32(buf, off); off = off + 4
	local force = readf32(buf, off); off = off + 4
	local px = readf32(buf, off); off = off + 4
	local py = readf32(buf, off); off = off + 4
	local pz = readf32(buf, off); off = off + 4

	local ids = table.create(n)
	for i = 1, n do
		ids[i] = readu32(buf, off); off = off + 4
	end

	return ids, force, Vector3.new(px, py, pz)
end

CollideCheck.encodeCollidePayload = encodeCollidePayload
CollideCheck.decodeCollidePayload = decodeCollidePayload

function CollideCheck.new(config: any, dispatch: (eventName: string, payload: buffer) -> ())
	local self = setmetatable({}, CollideCheck)
	self.Config = config or {}
	self.Dispatch = dispatch
	self.Tracked = {}
	self.LastVelocities = {}
	return self
end

function CollideCheck:Track(part: BasePart, partId: number?)
	if not part then return end
	if self.Tracked[part] then return end

	local id = partId
	if type(id) ~= "number" then
		id = part:GetAttribute("ObjectId")
	end
	if type(id) ~= "number" then
		id = part:GetAttribute("PartIndex")
	end
	if type(id) ~= "number" then
		id = 0
	end

	local vel = part.AssemblyLinearVelocity
	self.Tracked[part] = { Id = id, LastVelocity = vel }
	self.LastVelocities[part] = vel
end

function CollideCheck:Untrack(part: BasePart)
	if not part then return end
	self.Tracked[part] = nil
	self.LastVelocities[part] = nil
end

function CollideCheck:Step()
	local cfg = self.Config
	local minForce = cfg.MinImpactForce or 100
	local eventName = cfg.EventName or "CollideEvent"
	local dt = cfg.CheckInterval or 0.1

	local g = workspace.Gravity
	local gravityVel = Vector3.new(0, -g * dt, 0)

	local toRemove: { BasePart } = {}

	for part, data in pairs(self.Tracked) do
		if not part or not part.Parent then
			ins(toRemove, part)
		else
			local currentVel = part.AssemblyLinearVelocity
			local lastVel = data.LastVelocity

			if lastVel then
				local deltaVel = currentVel - lastVel - gravityVel
				local impactForce = deltaVel.Magnitude * part.AssemblyMass

				if impactForce >= minForce then
					local payload = encodeCollidePayload({ data.Id }, impactForce, part.Position)
					if self.Dispatch then
						self.Dispatch(eventName, payload)
					end
					ins(toRemove, part)
				else
					data.LastVelocity = currentVel
					self.LastVelocities[part] = currentVel
				end
			else
				data.LastVelocity = currentVel
				self.LastVelocities[part] = currentVel
			end
		end
	end

	for i = 1, #toRemove do
		local p = toRemove[i]
		if p then
			self.Tracked[p] = nil
			self.LastVelocities[p] = nil
		end
	end
end

CollideCheck.Poll = CollideCheck.Step

return CollideCheck

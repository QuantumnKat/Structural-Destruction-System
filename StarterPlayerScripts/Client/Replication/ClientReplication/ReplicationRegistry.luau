--!strict
-- EditorSync: refactor-v1
--!native
return function(ClientReplication: any, deps: any)
local LOCAL_ANCHOR = deps.LOCAL_ANCHOR
local RESOLVE_COOLDOWN = deps.RESOLVE_COOLDOWN
local sampleBuffer = deps.sampleBuffer
local osclock = deps.osclock
function ClientReplication:_watch(part: BasePart)
	if self._watchers[part] then return end
	self._watchers[part] = part:GetAttributeChangedSignal("ObjectId"):Connect(function()
		local v = part:GetAttribute("ObjectId")
		if typeof(v) == "number" then
			self:RegisterPart(v, part)
		end
	end)
end

function ClientReplication:WatchPart(part: BasePart)
	if not part then return end
	self:_watch(part)
	local oid = part:GetAttribute("ObjectId")
	if typeof(oid) == "number" then
		self:RegisterPart(oid, part)
	end
end

function ClientReplication:RegisterPart(partId: number, part: BasePart)
	if not part then return end

	local ids = self._partIds
	local old = ids[part]
	if old ~= nil and old ~= partId then
		if self.DynamicParts[old] == part then
			self.DynamicParts[old] = nil
		end
		self.Targets[old] = nil
	end
	local prev = self.DynamicParts[partId]
	if prev ~= nil and prev ~= part then
		if prev:GetAttribute("Proxy") == true then
			ids[prev] = nil
			local c = self._watchers[prev]
			if c then
				c:Disconnect()
				self._watchers[prev] = nil
			end
			prev:Destroy()
		elseif part:GetAttribute("Proxy") == true and prev.Parent ~= nil then
			part:Destroy()
			return
		end
	end

	ids[part] = partId
	self.DynamicParts[partId] = part
	self:_watch(part)

	if LOCAL_ANCHOR then
		part.Anchored = true
	end

	local data = self.Targets[partId]
	if data then
		local cf: CFrame = data.C[data.Head]
		local clockOffset: number? = self._clockOffset
		if clockOffset then
			cf = sampleBuffer(data, osclock() - clockOffset - data.Delay, data.Conf)
		end
		part.CFrame = cf
		data.Cur = cf
		data.Idle = false
	end
end

function ClientReplication:ForgetPart(part: BasePart)
	local id = self._partIds[part]
	if id ~= nil then
		if self.DynamicParts[id] == part then
			self.DynamicParts[id] = nil
			self.Targets[id] = nil
		end
		self._partIds[part] = nil
	end
	local c = self._watchers[part]
	if c then
		c:Disconnect()
		self._watchers[part] = nil
	end
end

function ClientReplication:SetResolver(fn: ((partId: number) -> BasePart?)?)
	self._resolver = fn
end

function ClientReplication:_tryResolve(partId: number, now: number): BasePart?
	local resolver = self._resolver
	if not resolver then return nil end
	local nextAt = self._resolveAt[partId]
	if nextAt and now < nextAt then return nil end
	self._resolveAt[partId] = now + RESOLVE_COOLDOWN

	local part = resolver(partId)
	if part and part.Parent then
		self:RegisterPart(partId, part)
		return part
	end
	return nil
end

function ClientReplication:UnregisterPart(partId: number)
	local part = self.DynamicParts[partId]
	if part then
		self:ForgetPart(part)
		if part.Parent then part:Destroy() end
	end
	self.DynamicParts[partId] = nil
	self.Targets[partId] = nil
end


end

--!strict
-- Process-local service locator. Server and client each have their own table.
local M = {}
local registry: {[string]: any} = {}

function M.Register(name: string, service: any)
	assert(type(name) == "string" and #name > 0, "service name required")
	assert(service ~= nil, "service required")
	registry[name] = service
end

function M.Get(name: string): any?
	return registry[name]
end

function M.Must(name: string): any
	local s = registry[name]
	assert(s ~= nil, "[Services] missing: " .. name)
	return s
end

function M.Clear()
	table.clear(registry)
end

return table.freeze(M)

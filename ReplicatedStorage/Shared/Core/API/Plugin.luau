--!strict
-- Public hook surface for other systems. Never bind Call to a remote.
local M = {}

local events: {[string]: {(...any) -> ()}} = {}
local commands: {[string]: (...any) -> any} = {}
local sealed = false

function M.On(name: string, fn: (...any) -> ())
	assert(type(name) == "string" and type(fn) == "function", "invalid hook")
	events[name] = events[name] or {}
	table.insert(events[name], fn)
	return function()
		local list = events[name]
		if not list then return end
		for i, f in list do
			if f == fn then
				table.remove(list, i)
				break
			end
		end
	end
end

function M.Emit(name: string, ...: any)
	local list = events[name]
	if not list then return end
	for _, fn in list do
		local ok, err = pcall(fn, ...)
		if not ok then
			warn("[Plugin] hook failed:", name, err)
		end
	end
end

function M.Register(name: string, fn: (...any) -> any)
	assert(not sealed, "plugin commands sealed")
	assert(type(name) == "string" and type(fn) == "function", "invalid command")
	assert(commands[name] == nil, "duplicate command")
	commands[name] = fn
end

function M.Call(name: string, ...: any): (boolean, any)
	local fn = commands[name]
	if not fn then
		return false, "UNKNOWN_COMMAND"
	end
	local ok, result = pcall(fn, ...)
	if not ok then
		return false, result
	end
	return true, result
end

function M.Seal()
	sealed = true
end

function M.Snapshot(): {commands: {string}, events: {string}}
	local cmds, evs = {}, {}
	for name in commands do table.insert(cmds, name) end
	for name in events do table.insert(evs, name) end
	table.sort(cmds)
	table.sort(evs)
	return { commands = cmds, events = evs }
end

return table.freeze(M)

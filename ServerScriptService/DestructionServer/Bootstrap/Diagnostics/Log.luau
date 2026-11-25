--!strict
--!native

-- Category logger. Info/Warn always print; Print respects runtime flags.

local Log: any = {}

local flags: { [string]: boolean } = {}
local lines: { string } = {}
local cap = 300
local head = 0
local count = 0

function Log.Init(ctx: any)
	cap = ctx.Config.Debug.LogLines
	for k, v in pairs(ctx.Config.Debug.Flags) do
		flags[k] = v
	end
end

local function store(line: string)
	head = head % cap + 1
	lines[head] = line
	if count < cap then count += 1 end
end

local function fmt(f: string, ...): string
	if select("#", ...) == 0 then return f end
	local ok, s = pcall(string.format, f, ...)
	return if ok then s else f
end

function Log.Info(cat: string, f: string, ...)
	local line = ("[%s] %s"):format(cat, fmt(f, ...))
	store(line)
	print(line)
end

function Log.Warn(cat: string, f: string, ...)
	local line = ("[%s] %s"):format(cat, fmt(f, ...))
	store("WARN " .. line)
	warn(line)
end

function Log.Print(cat: string, f: string, ...)
	if not flags[cat] then return end
	Log.Info(cat, f, ...)
end

function Log.SetFlag(cat: string, on: boolean)
	flags[cat] = on
end

function Log.GetFlags(): { [string]: boolean }
	return table.clone(flags)
end

function Log.Tail(n: number?): { string }
	local want = math.min(n or 50, count)
	local out: { string } = {}
	for i = want - 1, 0, -1 do
		local idx = (head - 1 - i) % cap + 1
		out[#out + 1] = lines[idx]
	end
	return out
end

return Log

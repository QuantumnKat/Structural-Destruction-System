--!strict

export type StateInfo = {
	Name: string,
	Bit: number,
}

local PhysicsState = {}

PhysicsState.Active    = 1      
PhysicsState.Sleeping  = 2      
PhysicsState.Frozen    = 4      
PhysicsState.Kinematic = 8      
PhysicsState.Culled    = 16     

local S = PhysicsState

PhysicsState.List = {
	{ Name = "Active",    Bit = S.Active    },
	{ Name = "Sleeping",  Bit = S.Sleeping  },
	{ Name = "Frozen",    Bit = S.Frozen    },
	{ Name = "Kinematic", Bit = S.Kinematic },
	{ Name = "Culled",    Bit = S.Culled    },
} :: { StateInfo }

PhysicsState.All = 0
for _, info in PhysicsState.List do
	PhysicsState.All = bit32.bor(PhysicsState.All, info.Bit)
end

local nameToBit: { [string]: number } = {}
local bitToName: { [number]: string } = {}
for _, info in PhysicsState.List do
	nameToBit[info.Name] = info.Bit
	bitToName[info.Bit] = info.Name
end

function PhysicsState.HasAll(value: number, mask: number): boolean
	return bit32.band(value, mask) == mask
end

function PhysicsState.HasAny(value: number, mask: number): boolean
	return bit32.band(value, mask) ~= 0
end

function PhysicsState.Is(value: number, state: number): boolean
	return bit32.band(value, state) ~= 0
end

function PhysicsState.Set(value: number, state: number): number
	return bit32.bor(value, state)
end

function PhysicsState.Clear(value: number, state: number): number
	return bit32.band(value, bit32.bnot(state))
end

function PhysicsState.Toggle(value: number, state: number): number
	return bit32.bxor(value, state)
end

function PhysicsState.Replace(value: number, state: number): number
	return bit32.bor(bit32.band(value, bit32.bnot(PhysicsState.All)), state)
end

function PhysicsState.Invert(value: number): number
	return bit32.band(bit32.bnot(value), PhysicsState.All)
end

function PhysicsState.FromName(name: string): number?
	return nameToBit[name]
end

function PhysicsState.ToName(bit: number): string?
	return bitToName[bit]
end

function PhysicsState.ToNames(value: number): { string }
	local names = {}
	for _, info in PhysicsState.List do
		if bit32.band(value, info.Bit) ~= 0 then
			table.insert(names, info.Name)
		end
	end
	return names
end

function PhysicsState.FromNames(names: { string }): number
	local mask = 0
	for _, name in names do
		local bit = nameToBit[name]
		assert(bit, string.format("[PhysicsState] unknown state '%s'", name))
		mask = bit32.bor(mask, bit)
	end
	return mask
end

return PhysicsState

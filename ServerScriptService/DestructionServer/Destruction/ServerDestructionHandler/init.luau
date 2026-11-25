--!strict
--!native

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapSerializer = require(ReplicatedStorage.Shared.Map.MapSerializer)
local ObjectConf = require(script.Parent.Parent.Objects.ObjectConf)
local ObjectManager = require(script.Parent.Parent.Objects.ObjectManager)
local NeighborTracker = require(ReplicatedStorage.Shared.Destruction.NeighborTracker)

local Constants = require(script.Parent.Support.Constants)
local PartIndexMap = require(script.Parent.Identity.PartIndexMap)
local PhysicsHelpers = require(script.Parent.Support.PhysicsHelpers)
local WeldTree = require(script.Parent.Structure.WeldTree)
local DebrisSpawner = require(script.Parent.Fragments.DebrisSpawner)
local Shatter = require(script.Parent.Fragments.Shatter)
local DisconnectHandler = require(script.Parent.Structure.DisconnectHandler)
local IslandActivator = require(script.Parent.Structure.IslandActivator)
local SyncDisconnected = require(script.Parent.Structure.SyncDisconnected)
local ForcePropagator = require(script.Parent.Structure.ForcePropagator)
local ChunkBreaker = require(script.Parent.Fragments.ChunkBreaker)
local HitShapeMod = require(script.Parent.Geometry.HitShape)
local FragmentManager = require(script.Parent.Fragments.FragmentManager)
local PartIds = require(script.Parent.Identity.PartIds)
local Thrust = require(script.Parent.Fragments.FragmentThrust)
local CollideCheck = require(script.Parent.Parent.Objects.CollideCheck)
local Thrust = require(script.Parent.Fragments.FragmentThrust)
local DebrisImpact = require(script.Parent.Fragments.DebrisImpact)

local typeOf = typeof

local DEBUG = false

local PROPAGATE_RADIUS = 40
local WEAK_HIT_RADIUS = 10
local WAKE_RADIUS = 15
local STRUCTURAL_TICK_DT = 0.2

local ServerDestructionHandler = {}

ServerDestructionHandler.Modules = {
	Constants = Constants,
	PartIndexMap = PartIndexMap,
	PhysicsHelpers = PhysicsHelpers,
	WeldTree = WeldTree,
	DebrisSpawner = DebrisSpawner,
	Shatter = Shatter,
	DisconnectHandler = DisconnectHandler,
	IslandActivator = IslandActivator,
	SyncDisconnected = SyncDisconnected,
	ForcePropagator = ForcePropagator,
	ChunkBreaker = ChunkBreaker,
	ChunkBreaker = ChunkBreaker,
	DebrisImpact = DebrisImpact,
}

local Helpers = require(script.DestructionHelpers)({
	ObjectConf = ObjectConf,
	ObjectManager = ObjectManager,
	NeighborTracker = NeighborTracker,
	ForcePropagator = ForcePropagator,
	PhysicsHelpers = PhysicsHelpers,
	Constants = Constants,
	MapSerializer = MapSerializer,
	WAKE_RADIUS = WAKE_RADIUS,
	DEBUG = DEBUG,
})

local resolveMapFolders = Helpers.resolveMapFolders
local fireDebris = Helpers.fireDebris

require(script.IndexedDamage)(ServerDestructionHandler, {
	Helpers = Helpers,
	PartIndexMap = PartIndexMap,
	ChunkBreaker = ChunkBreaker,
	Shatter = Shatter,
	SyncDisconnected = SyncDisconnected,
	FragmentManager = FragmentManager,
	Thrust = Thrust,
	ForcePropagator = ForcePropagator,
	HitShapeMod = HitShapeMod,
	ObjectManager = ObjectManager,
	PROPAGATE_RADIUS = PROPAGATE_RADIUS,
	WEAK_HIT_RADIUS = WEAK_HIT_RADIUS,
	WAKE_RADIUS = WAKE_RADIUS,
	DEBUG = DEBUG,
})

local ctx: any = { graph = nil, event = nil, active = nil }
local warnedNoCtx = false

function ServerDestructionHandler.SetContext(graph: any, replicationEvent: RemoteEvent?, ActiveParts: { BasePart })
	ctx.graph = graph
	ctx.event = replicationEvent
	ctx.active = ActiveParts
	PartIds.Init(replicationEvent, ActiveParts)
	FragmentManager.Init(graph, replicationEvent, ActiveParts)
	FragmentManager.SetGraph(graph)
	Thrust.Init(ActiveParts, replicationEvent)

	DebrisImpact.Init({
		active = ActiveParts,
		explode = function(pos: Vector3, radius: number, force: number, opts: any): boolean
			return ServerDestructionHandler.Explode(graph, pos, radius, force, replicationEvent, ActiveParts, opts)
		end,
		fireDebris = function(list: { any })
			fireDebris(replicationEvent, list)
		end,
	})
end

function ServerDestructionHandler.GetContext(): (any, RemoteEvent?, { BasePart }?)
	return ctx.graph, ctx.event, ctx.active
end

local _staticDamageCb: ((partIndex: number, userId: number, damage: number) -> ())? = nil

ServerDestructionHandler.PartIds = PartIds

require(script.ShapeDamage)(ServerDestructionHandler, {
	Helpers = Helpers,
	PartIndexMap = PartIndexMap,
	ChunkBreaker = ChunkBreaker,
	Shatter = Shatter,
	SyncDisconnected = SyncDisconnected,
	FragmentManager = FragmentManager,
	Thrust = Thrust,
	ForcePropagator = ForcePropagator,
	HitShapeMod = HitShapeMod,
	ObjectManager = ObjectManager,
	PROPAGATE_RADIUS = PROPAGATE_RADIUS,
	WEAK_HIT_RADIUS = WEAK_HIT_RADIUS,
	WAKE_RADIUS = WAKE_RADIUS,
	DEBUG = DEBUG,
})

local shapeFromPart = require(script.Parent.Geometry.ImpactShape)

local function findImpactor(id: number, physicalPartMap: { [number]: BasePart }, ActiveParts: { BasePart }): BasePart?
	local offset: number = Constants.FALLING_ID_OFFSET
	if id >= offset then
		local p = physicalPartMap[id - offset]
		if p and p.Parent then return p end
	end
	for i = 1, #ActiveParts do
		local p = ActiveParts[i]
		if p and p.Parent and p:GetAttribute("ObjectId") == id then
			return p
		end
	end
	return nil
end

function ServerDestructionHandler.HandleCollisionImpacts(payload: buffer)
	local graph, ActiveParts = ctx.graph, ctx.active
	if not graph or not ActiveParts then
		if not warnedNoCtx then
			warnedNoCtx = true
			warn("[ServerDestructionHandler] HandleCollisionImpacts: hãy gọi SetContext(graph, event, ActiveParts) trước")
		end
		return
	end

	local ids, force, pos = CollideCheck.decodeCollidePayload(payload)
	local camFolder, mapFolder = resolveMapFolders()
	if not camFolder then return end
	local physicalPartMap = PartIndexMap.Build(mapFolder or camFolder)
	local offset: number = Constants.FALLING_ID_OFFSET

	for i = 1, #ids do
		local id = ids[i]
		local impactor = findImpactor(id, physicalPartMap, ActiveParts)

		local chainUid: number? = nil
		local chainDmg: number? = nil
		if impactor then
			local uid = impactor:GetAttribute("AttackerUserId")
			local dmg = impactor:GetAttribute("AttributionDamage")
			if type(uid) == "number" then
				chainUid = uid
				chainDmg = if type(dmg) == "number" then dmg else force
			end
		end

		local exclude: { [number]: boolean } = {}
		if id >= offset then exclude[id - offset] = true end
		local selfIdx = impactor and impactor:GetAttribute("PartIndex")
		if typeOf(selfIdx) == "number" then exclude[selfIdx] = true end

		ServerDestructionHandler.HitShape(
			graph,
			shapeFromPart(impactor, pos),
			force,
			ctx.event,
			ActiveParts,
			{
				ExcludeIdx = exclude,
				DirectionalBias = 0.5,
				ExcludeIds = { [id] = true },
				ExcludeFragmentId = if impactor then impactor:GetAttribute("FragmentId") else nil,
				AttackerUserId = chainUid,
				AttributionDamage = chainDmg,
			}
		)
	end
end

ServerDestructionHandler.ShapeFromPart = shapeFromPart

function ServerDestructionHandler.BreakByShape(
	graph: any,
	shape: any,
	force: number,
	replicationEvent: RemoteEvent?,
	ActiveParts: { BasePart },
	opts: any?
): boolean
	return ServerDestructionHandler.HitShape(graph, shape, force, replicationEvent, ActiveParts, opts)
end

function ServerDestructionHandler.Explode(
	graph: any,
	pos: Vector3,
	radius: number,
	force: number,
	replicationEvent: RemoteEvent?,
	ActiveParts: { BasePart },
	opts: any?
): boolean
	local shape = { Type = "Sphere", CFrame = CFrame.new(pos), Radius = radius, Falloff = "Smooth" }
	return ServerDestructionHandler.HitShape(graph, shape, force, replicationEvent, ActiveParts, opts)
end

local function segmentShape(kind: string, a: Vector3, b: Vector3, radius: number): any?
	local len = (b - a).Magnitude
	if len < 1e-3 then return nil end
	return { Type = kind, CFrame = CFrame.lookAt(a, b), Length = len, Radius = radius }
end

function ServerDestructionHandler.BreakLine(
	graph: any,
	a: Vector3,
	b: Vector3,
	radius: number,
	force: number,
	replicationEvent: RemoteEvent?,
	ActiveParts: { BasePart },
	opts: any?
): boolean
	local shape = segmentShape("Line", a, b, radius)
	if not shape then return false end
	return ServerDestructionHandler.HitShape(graph, shape, force, replicationEvent, ActiveParts, opts)
end

function ServerDestructionHandler.BreakCapsule(
	graph: any,
	a: Vector3,
	b: Vector3,
	radius: number,
	force: number,
	replicationEvent: RemoteEvent?,
	ActiveParts: { BasePart },
	opts: any?
): boolean
	local shape = segmentShape("Capsule", a, b, radius)
	if not shape then return false end
	return ServerDestructionHandler.HitShape(graph, shape, force, replicationEvent, ActiveParts, opts)
end

function ServerDestructionHandler.BreakCone(
	graph: any,
	origin: Vector3,
	direction: Vector3,
	length: number,
	halfAngle: number,
	force: number,
	replicationEvent: RemoteEvent?,
	ActiveParts: { BasePart },
	opts: any?
): boolean
	if direction.Magnitude < 1e-3 then return false end
	local shape = {
		Type = "Cone",
		CFrame = CFrame.lookAt(origin, origin + direction.Unit),
		Length = length,
		HalfAngle = halfAngle,
	}
	return ServerDestructionHandler.HitShape(graph, shape, force, replicationEvent, ActiveParts, opts)
end

function ServerDestructionHandler.CheckStability(
	graph: any,
	physicalPartMap: { [number]: BasePart },
	camFolder: Instance,
	ActiveParts: { BasePart },
	replicationEvent: RemoteEvent
)
	if not graph then return end

	graph:Tick(STRUCTURAL_TICK_DT)

	local toCollapse: { number } = {}
	local debrisList: { any } = {}
	SyncDisconnected.SyncAndActivateDisconnected(
		graph, physicalPartMap, ActiveParts, toCollapse,
		-1, debrisList, camFolder, replicationEvent
	)

	if replicationEvent then
		if #toCollapse > 0 then
			replicationEvent:FireAllClients("COLLAPSE_PARTS", toCollapse)
		end
		fireDebris(replicationEvent, debrisList)
	end
end

return ServerDestructionHandler
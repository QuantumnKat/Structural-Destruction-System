--!strict
return {
	Remote = {
		Event = "ReplicationEvent",
		Debug = "DebugAPI",
	},

	Join = {
		Delay = 1,
		WaitCharacter = true,
		SnapshotDelay = 1.5,
		MaxWaitReady = 30,
	},

	PartMap = {
		RefreshInterval = 1.0,
	},

	Stability = {
		Enabled = true,
		Interval = 0.2,
	},

	Collide = { Mode = "Shape" },

	Requests = {
		Validate = true,
		MaxForce = 20000,
		MaxRadius = 30,
		MaxPerSecond = 8,
		MaxDistance = 300,
		RequireCharacter = true,
	},

	Exports = { Globals = true },

	Debug = {
		Enabled = true,
		AllowInStudio = true,
		AllowedUserIds = {},
		LogLines = 300,
		DrawTTL = 5,
		MaxDrawParts = 600,
		DrawOnHit = false,
		Flags = {
			Boot = true, Map = true, Requests = true,
			Hits = true, Collapse = false, Replication = false, Thrust = false, Debug = true,
		},
		ProbeSample = 48,
		ProbeTimeout = 3,
		ProbeDriftStuds = 3,
	},
}

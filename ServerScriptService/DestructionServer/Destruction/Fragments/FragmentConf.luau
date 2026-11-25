--!strict

return {
	Enabled = true,

	ExtraIdBase = 1073741824,

	Trigger = {
		MinCollapseParts = 6,
		MinCollapseMass  = 0,
		MinForce         = 0,
	},

	Launch = {
		VelocityPerForce = 0.02,
		MaxSpeed   = 120,   -- studs/s
		MaxSpin    = 12,    -- rad/s
		UpwardBias = 0.15,
		Jitter     = 0.05,
	},

	Cluster = {
		TearTime           = 0.05,
		BindScale          = 1.0,
		MaxDamageToStick   = 0.85,
		MaxPartsPerCluster = 40,
		MinWeldParts       = 2,
		MaxAvgDamage       = 0.6,
		ShatterEnergyRatio = 3.0,
		WeldMode           = "Tree",
		NoWeldMaterials    = { Glass = false },
		MaxWeldsPerEvent   = 400,
	},

	Debris = {
		HitEnabled       = true,
		MaxSplitsPerHit  = 24,
		SplitForceRatio  = 1.0,
		FullShatterRatio = 3.0,
		MinPieceVolume   = 0.35,
		MinPieceExtent   = 0.4,
		PieceSpeed       = 0.01,
		MaxPieceSpeed    = 60,
		TrackCollisions  = false,
	},

	Vanish = {
		StepInterval    = 0.5,
		MaxPartsPerStep = 200,
		TinyVolume      = 0.35,
		TinyExtent      = 0.4,
		TinyLifetime    = 6.0,
		TinySettledTTL  = 1.5,
		LifetimeEnabled = false,
		BaseLifetime    = 90,
		RefVolume       = 8,
		MinLifetime     = 8,
		MaxLifetime     = 120,
	},

	Log = {
		Enabled      = true,
		SegmentBytes = 16384,
		Segments     = 8,
	},

	Snapshot = {
		Enabled            = true,
		Interval           = 30,
		MinChangedEvents   = 1,
		MaxSnapshots       = 3,
		IncludePoses       = true,
		MaxPoseRecords     = 512,
		ScanGraphOnCapture = true,
	},

	Ids = {
		Tag                = "DynPart",
		AutoAssign         = true,
		AnnounceSpawns     = true,
		MaxSpawnPerStep    = 128,
		MaxQueue           = 8192,
		SpawnFlushInterval = 0.1,
		ScanBudget         = 256,
		Audit = {
			Enabled = true,
			Interval = 10,
			AutoFix = true,
			Warn = true,
		},
	},

	Thrust = {
		Enabled       = true,
		Mode          = "Sustained",
		MinParts      = 1,
		LaunchScale   = 0.6,
		SpeedPerForce = 0.02,
		MassExponent  = 0.5,
		MaxSpeed      = 140,         -- studs/s
		MaxSpin       = 14,          -- rad/s
		Duration      = 0.18,
		DecayPower    = 1.5,
		UpBias        = 0.2,
		Jitter        = 0.08,
		Spin          = 4,
		MaxActive     = 600,
		MaxPerStep    = 200,

		Shockwave = {
			Enabled     = true,
			Scale       = 0.5,
			RadiusScale = 1.3,
			AffectDebris = true,
		},
		Players = {
			Enabled       = true,
			SpeedPerForce = 0.005,
			MaxSpeed      = 55,
			UpBoost       = 14,
		},
	},
}

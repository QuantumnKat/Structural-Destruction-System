--!strict

local Boot = script.Parent:WaitForChild("Runtime")
local ClientController = require(Boot:WaitForChild("ClientController") :: ModuleScript)

ClientController.Start()
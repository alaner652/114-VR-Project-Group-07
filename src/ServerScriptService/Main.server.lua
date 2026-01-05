-- Main.server.lua
-- Server entry point
local ServerScriptService = game:GetService("ServerScriptService")
local SystemFolder = ServerScriptService:WaitForChild("Systems")

-- Core systems
local CollisionGroupSync = require(SystemFolder:WaitForChild("CollisionGroupSync"))
local DragOwnershipService = require(SystemFolder:WaitForChild("DragOwnershipService"))
local TagModuleLoader = require(SystemFolder:WaitForChild("TagModuleLoader"))

-- =====================
-- Boot sequence
-- =====================
CollisionGroupSync.init()
DragOwnershipService.init()
TagModuleLoader.init(SystemFolder:WaitForChild("Modules"))

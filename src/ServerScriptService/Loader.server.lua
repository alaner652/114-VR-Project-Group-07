-- Main.server.lua
-- Server entry point
local ServerScriptService = game:GetService("ServerScriptService")
local SystemFolder = ServerScriptService:WaitForChild("Systems")

-- Core systems
local CollisionHandler = require(SystemFolder:WaitForChild("CollisionHandler"))
local DragHandler = require(SystemFolder:WaitForChild("DragHandler"))
local NPCHandler = require(SystemFolder:WaitForChild("NPCHandler"))
local ObjectsHandler = require(SystemFolder:WaitForChild("ObjectsHandler"))

-- =====================
-- Boot sequence
-- =====================
CollisionHandler.init()
DragHandler.init()
ObjectsHandler.init()
task.wait(1)
NPCHandler.init()

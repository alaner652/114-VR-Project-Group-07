local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local Utils = require(script.Parent.Utils)

local NPCSpawn = workspace:WaitForChild("NPCSystem"):WaitForChild("NPCSpawn")

-- =====================
-- Config
-- =====================

local PATH_PARAMS = {
	AgentRadius = 3,
	AgentHeight = 5,
	AgentCanJump = true,
}

local MAX_MOVE_TIME = 5
local MAX_RETRY = 3

-- =====================
-- NPC
-- =====================

local NPC = {}
NPC.__index = NPC

function NPC.new(context)
	local self = setmetatable({
		seat = context.seat,
		hitbox = context.hitbox,

		model = Utils:spawnModel(),
		humanoid = nil,

		waypoints = nil,
		currentIndex = 1,
		retryCount = 0,
	}, NPC)

	self.humanoid = self.model:FindFirstChildOfClass("Humanoid")
	self.model:SetPrimaryPartCFrame(NPCSpawn.CFrame)

	self:_start()
	return self
end

-- =====================
-- Path
-- =====================

function NPC:_computePath()
	local path = PathfindingService:CreatePath(PATH_PARAMS)
	path:ComputeAsync(NPCSpawn.Position, self.hitbox.Position)

	if path.Status ~= Enum.PathStatus.Success then
		return nil
	end

	return path:GetWaypoints()
end

-- =====================
-- Safe Move
-- =====================

function NPC:_moveTo(position)
	if not self.humanoid then
		return false
	end

	local finished = false
	local reached = false

	local conn
	conn = self.humanoid.MoveToFinished:Connect(function(ok)
		reached = ok
		finished = true
	end)

	self.humanoid:MoveTo(position)

	local start = os.clock()
	while not finished and os.clock() - start < MAX_MOVE_TIME do
		task.wait()
	end

	if conn then
		conn:Disconnect()
	end

	return finished and reached
end

-- =====================
-- Core Loop
-- =====================

function NPC:_start()
	self.waypoints = self:_computePath()
	if not self.waypoints then
		warn("[NPC] Path failed, destroying")
		self:Destroy()
		return
	end

	task.spawn(function()
		while self.currentIndex <= #self.waypoints do
			local wp = self.waypoints[self.currentIndex]

			local ok = self:_moveTo(wp.Position)
			if ok then
				-- 成功前進
				self.currentIndex += 1
				self.retryCount = 0
			else
				-- 被打斷
				self.retryCount += 1
				warn(
					("[NPC] Move interrupted (retry %d/%d) at waypoint %d"):format(
						self.retryCount,
						MAX_RETRY,
						self.currentIndex
					)
				)

				if self.retryCount >= MAX_RETRY then
					warn("[NPC] Too many retries, destroying NPC")
					self:Destroy()
					return
				end

				-- 回到上一個 waypoint（但不小於 1）
				self.currentIndex = math.max(1, self.currentIndex - 1)
				RunService.Heartbeat:Wait()
			end
		end

		-- 抵達目標
		self:_sit()
	end)
end

-- =====================
-- Sit
-- =====================

function NPC:_sit()
	local root = self.model.PrimaryPart
	if not root then
		self:Destroy()
		return
	end

	if self.seat:IsA("Seat") and self.humanoid then
		self.seat:Sit(self.humanoid)
	else
		local offsetY = (self.seat.Size.Y * 0.5) + (root.Size.Y * 0.5)
		root.CFrame = self.seat.CFrame * CFrame.new(0, offsetY, 0)

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = self.seat
		weld.Part1 = root
		weld.Parent = root

		if self.humanoid then
			self.humanoid.Sit = true
		end
	end

	print("[NPC] Seated successfully")
end

-- =====================
-- Destroy
-- =====================

function NPC:Destroy()
	if self.model then
		self.model:Destroy()
		self.model = nil
	end

	if self.seat then
		self.seat:SetAttribute("Active", false)
	end

	setmetatable(self, nil)
end

return NPC

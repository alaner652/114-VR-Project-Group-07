-- ======================================================
-- Services
-- ======================================================
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NPCFolder = ReplicatedStorage:WaitForChild("NPCs")

local NPCSpawn = workspace:WaitForChild("NPCSystem"):WaitForChild("NPCSpawn")
local NPCContainer = workspace:WaitForChild("NPCs")

-- ======================================================
-- Config
-- ======================================================
local LEAVE_TIME = 2

local PATH_PARAMS = {
	AgentRadius = 3,
	AgentHeight = 5,
	AgentCanJump = true,
}

-- ======================================================
-- NPC Class
-- ======================================================
local NPC = {}
NPC.__index = NPC

-- ======================================================
-- Utils
-- ======================================================

local function spawnModel()
	local rig = NPCFolder:WaitForChild("Rig")
	local model = rig:Clone()
	model.Parent = NPCContainer
	return model
end

local function reverseWaypointsSkipLast(waypoints)
	local reversed = {}
	for i = #waypoints - 1, 1, -1 do
		reversed[#reversed + 1] = waypoints[i]
	end
	return reversed
end

-- ======================================================
-- Friend Avatar Utils
-- ======================================================

local function getRandomFriendUserId()
	local players = Players:GetPlayers()
	if #players == 0 then
		return nil
	end

	local basePlayer = players[math.random(#players)]

	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(basePlayer.UserId)
	end)
	if not ok then
		return nil
	end

	local friends = {}
	for _, friend in ipairs(pages:GetCurrentPage()) do
		table.insert(friends, friend)
	end

	if #friends == 0 then
		return nil
	end

	return friends[math.random(#friends)].Id
end

local function applyRandomFriendAppearance(humanoid)
	local userId = getRandomFriendUserId()
	if not userId then
		return
	end

	task.spawn(function()
		local ok, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(userId)
		end)
		if ok and desc then
			humanoid:ApplyDescription(desc)
		end
	end)
end

-- ======================================================
-- Constructor
-- ======================================================

function NPC.new(context)
	local self = setmetatable({
		seat = context.seat,
		hitbox = context.hitbox,

		model = spawnModel(),
		humanoid = nil,

		enterWaypoints = nil,
		seated = false,
		moving = false,

		retryCount = 0,
	}, NPC)

	self.humanoid = self.model:FindFirstChildOfClass("Humanoid")
	self.model:SetPrimaryPartCFrame(NPCSpawn.CFrame)

	if self.humanoid then
		applyRandomFriendAppearance(self.humanoid)
	end

	self:_enterShop()
	return self
end

-- ======================================================
-- Pathfinding
-- ======================================================

function NPC:_computePath(startPos, goalPos)
	local path = PathfindingService:CreatePath(PATH_PARAMS)
	path:ComputeAsync(startPos, goalPos)

	if path.Status ~= Enum.PathStatus.Success then
		return nil
	end

	return path:GetWaypoints()
end

-- ======================================================
-- Movement
-- ======================================================

function NPC:_followWaypoints(waypoints, onSuccess, onFail)
	if self.moving then
		return
	end
	self.moving = true

	task.spawn(function()
		for _, wp in ipairs(waypoints) do
			if not self.humanoid or not self.humanoid.Parent then
				self.moving = false
				if onFail then
					onFail("humanoid missing")
				end
				return
			end

			self.humanoid:MoveTo(wp.Position)
			local reached = self.humanoid.MoveToFinished:Wait()

			if not reached then
				self.moving = false
				if onFail then
					onFail("interrupted")
				end
				return
			end
		end

		self.moving = false
		if onSuccess then
			onSuccess()
		end
	end)
end

-- ======================================================
-- Behaviour
-- ======================================================

function NPC:_enterShop()
	local waypoints = self:_computePath(NPCSpawn.Position, self.hitbox.Position)
	if not waypoints then
		self:Destroy()
		return
	end

	self.enterWaypoints = waypoints

	self:_followWaypoints(waypoints, function()
		self:_sit()
	end, function()
		self.retryCount += 1
		if self.retryCount > 1 then
			self:Destroy()
			return
		end
		task.wait(0.5)
		self:_enterShop()
	end)
end

function NPC:_sit()
	if self.seated then
		return
	end
	self.seated = true

	local root = self.model.PrimaryPart
	if not root then
		return
	end

	local weld = Instance.new("Motor6D")
	weld.Name = "SeatWeld"
	weld.Part0 = self.seat
	weld.Part1 = root
	weld.C0 = CFrame.new(0, 3, 0)
	weld.Parent = root

	if self.humanoid then
		self.humanoid.Sit = true
	end

	task.delay(LEAVE_TIME, function()
		if self.model then
			self:startLeaving()
		end
	end)
end

function NPC:startLeaving()
	if not self.enterWaypoints then
		self:Destroy()
		return
	end

	local root = self.model.PrimaryPart
	if not root then
		self:Destroy()
		return
	end

	local weld = root:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end

	if self.humanoid then
		self.humanoid.Sit = false
	end

	local backWaypoints = reverseWaypointsSkipLast(self.enterWaypoints)

	self:_followWaypoints(backWaypoints, function()
		self:Destroy()
	end, function()
		self:Destroy()
	end)
end

-- ======================================================
-- Cleanup
-- ======================================================

function NPC:Destroy()
	if self.model then
		self.model:Destroy()
		self.model = nil
	end

	self.humanoid = nil
	self.enterWaypoints = nil
	self.seat:SetAttribute("Active", false)

	setmetatable(self, nil)
end

return NPC

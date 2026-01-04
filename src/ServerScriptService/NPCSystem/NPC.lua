local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NPCFolder = ReplicatedStorage:WaitForChild("NPCs")

local NPCSpawn = workspace:WaitForChild("NPCSystem"):WaitForChild("NPCSpawn")
local NPCContainer = workspace:WaitForChild("NPCs")

local WAIT_FOOD_TIME = 120
local EAT_TIME = 20

local PATH_PARAMS = {
	AgentRadius = 3,
	AgentHeight = 5,
	AgentCanJump = true,
}
local State = {
	ENTERING = "ENTERING",
	WAITING_FOOD = "WAITING_FOOD",
	EATING = "EATING",
	LEAVING = "LEAVING",
	DEAD = "DEAD",
}

local NPC = {}
NPC.__index = NPC

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

		if ok and desc and humanoid and humanoid.Parent then
			humanoid:ApplyDescription(desc)
		end
	end)
end

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

local function removeDraggableTagRecursive(model: Model)
	if CollectionService:HasTag(model, "Draggable") then
		CollectionService:RemoveTag(model, "Draggable")
	end

	for _, inst in ipairs(model:GetDescendants()) do
		if CollectionService:HasTag(inst, "Draggable") then
			CollectionService:RemoveTag(inst, "Draggable")
		end
	end
end

function NPC.new(context)
	local self = setmetatable({
		seat = context.seat,
		hitbox = context.hitbox,

		model = spawnModel(),
		humanoid = nil,

		enterWaypoints = nil,
		moving = false,

		state = State.ENTERING,
		stateTimeLeft = 0,
		stateLoopRunning = false,

		foodWeld = nil,
		retryCount = 0,
	}, NPC)

	self.humanoid = self.model:FindFirstChildOfClass("Humanoid")
	self.model:SetPrimaryPartCFrame(NPCSpawn.CFrame)

	if self.humanoid then
		applyRandomFriendAppearance(self.humanoid)
	end

	self:_enterShop()
	self:_startStateLoop()

	return self
end

function NPC:_setState(newState, time)
	if self.state == State.DEAD then
		return
	end

	self.state = newState
	self.stateTimeLeft = time or 0

	if self.humanoid then
		self.humanoid.DisplayName = ""
	end

	if newState == State.WAITING_FOOD then
		self:_onWaitingFood()
	elseif newState == State.EATING then
		self:_onEating()
	elseif newState == State.LEAVING then
		self:_onLeaving()
	end
end

function NPC:_startStateLoop()
	if self.stateLoopRunning then
		return
	end
	self.stateLoopRunning = true

	task.spawn(function()
		while self.model and self.state ~= State.DEAD do
			if self.stateTimeLeft > 0 then
				if self.humanoid then
					self.humanoid.DisplayName = string.format("%s (%ds)", self.state, self.stateTimeLeft)
				end
				task.wait(1)
				self.stateTimeLeft -= 1
			else
				if self.state == State.WAITING_FOOD or self.state == State.EATING then
					self:_setState(State.LEAVING)
				else
					task.wait(0.2)
				end
			end
		end
	end)
end

function NPC:_computePath(startPos, goalPos)
	local path = PathfindingService:CreatePath(PATH_PARAMS)
	path:ComputeAsync(startPos, goalPos)
	if path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	return path:GetWaypoints()
end

function NPC:_followWaypoints(waypoints, onSuccess)
	if self.moving then
		return
	end
	self.moving = true

	task.spawn(function()
		for _, wp in ipairs(waypoints) do
			if not self.humanoid or not self.humanoid.Parent then
				self.moving = false
				return
			end
			self.humanoid:MoveTo(wp.Position)
			if not self.humanoid.MoveToFinished:Wait() then
				self.moving = false
				return
			end
		end
		self.moving = false
		if onSuccess then
			onSuccess()
		end
	end)
end

function NPC:_enterShop()
	local waypoints = self:_computePath(NPCSpawn.Position, self.hitbox.Position)
	if not waypoints then
		self:Destroy()
		return
	end

	self.enterWaypoints = waypoints
	self:_followWaypoints(waypoints, function()
		self:_sit()
	end)
end

function NPC:_sit()
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

	self:_bindServeDetector()
	self:_setState(State.WAITING_FOOD, WAIT_FOOD_TIME)
end

function NPC:_bindServeDetector()
	self.hitbox.Touched:Connect(function(hit)
		if self.state ~= State.WAITING_FOOD then
			return
		end

		local model = hit:FindFirstAncestorOfClass("Model")
		if not model then
			return
		end

		if not CollectionService:HasTag(model, "Ramen") then
			return
		end

		if model:GetAttribute("Completed") ~= true then
			return
		end

		removeDraggableTagRecursive(model)
		self:_serve(model)
	end)
end

function NPC:_serve(ramenModel)
	local npcRoot = self.model.PrimaryPart
	local ramenRoot = ramenModel.PrimaryPart

	if npcRoot and ramenRoot then
		local weld = Instance.new("Motor6D")
		weld.Name = "FoodWeld"
		weld.Part0 = npcRoot
		weld.Part1 = ramenRoot
		weld.C0 = CFrame.new(0, -1.5, -2)
		weld.Parent = npcRoot
		self.foodWeld = weld
	end

	self:_setState(State.EATING, EAT_TIME)
end

function NPC:_onWaitingFood() end

function NPC:_onEating() end

function NPC:_onLeaving()
	if self.humanoid then
		self.humanoid.DisplayName = ""
		self.humanoid.Sit = false
	end

	local root = self.model.PrimaryPart
	if root then
		local seatWeld = root:FindFirstChild("SeatWeld")
		if seatWeld then
			seatWeld:Destroy()
		end
	end

	if self.foodWeld then
		self.foodWeld:Destroy()
		self.foodWeld = nil
	end

	if not self.enterWaypoints then
		self:Destroy()
		return
	end

	local back = reverseWaypointsSkipLast(self.enterWaypoints)
	self:_followWaypoints(back, function()
		self:Destroy()
	end)
end

function NPC:Destroy()
	self.state = State.DEAD

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

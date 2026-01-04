local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCFolder = ReplicatedStorage:WaitForChild("NPCs")
local NPCSpawn = workspace:WaitForChild("NPCSystem"):WaitForChild("NPCSpawn")
local NPCContainer = workspace:WaitForChild("NPCs")

local WAIT_FOOD_TIME = 120
local EAT_TIME = 2

local SERVE_BOX_SIZE = Vector3.new(4, 2, 3)
local SERVE_BOX_OFFSET = CFrame.new(0, -0.6, -2)
local SERVE_INTERVAL = 2

local PATH_PARAMS = {
	AgentRadius = 3,
	AgentHeight = 5,
	AgentCanJump = true,
}

local State = {
	ENTERING = "ENTERING",
	WAITING_FOOD = "WAITING_FOOD",
	SERVING = "SERVING",
	EATING = "EATING",
	LEAVING = "LEAVING",
	DEAD = "DEAD",
}

local NPC = {}
NPC.__index = NPC

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

local function getRandomFriendUserId()
	local players = Players:GetPlayers()
	if #players == 0 then
		return nil
	end

	local base = players[math.random(#players)]
	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(base.UserId)
	end)
	if not ok then
		return nil
	end

	local list = {}
	for _, f in ipairs(pages:GetCurrentPage()) do
		list[#list + 1] = f
	end
	if #list == 0 then
		return nil
	end

	return list[math.random(#list)].Id
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

		food = nil,
		foodWeld = nil,

		serveRayTask = nil,
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

	self:_setState(State.WAITING_FOOD, WAIT_FOOD_TIME)
	self:_startServeBox()
end

function NPC:_startServeBox()
	if self.serveBoxTask then
		return
	end

	local root = self.model.HumanoidRootPart
	if not root then
		return
	end

	local box = Instance.new("Part")
	box.Name = "__ServeBox"
	box.Anchored = true
	box.CanCollide = false
	box.CanTouch = false
	box.CastShadow = false
	box.Transparency = 0.5
	box.Size = SERVE_BOX_SIZE
	box.Parent = workspace

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		self.model,
		self.seat,
		box,
	}

	self.serveBoxTask = task.spawn(function()
		RunService.Heartbeat:Wait()

		while self.model and self.state == State.WAITING_FOOD do
			if not self.model.PrimaryPart then
				break
			end
			box.CFrame = self.model.PrimaryPart.CFrame * SERVE_BOX_OFFSET

			local parts = workspace:GetPartsInPart(box, params)

			for _, part in ipairs(parts) do
				local model = part:FindFirstAncestorOfClass("Model")
				if
					model
					and CollectionService:HasTag(model, "Ramen")
					and model:GetAttribute("Completed") == true
					and model:GetAttribute("BeingDragged") ~= true
				then
					box:Destroy()
					self.serveBoxTask = nil

					self:_setState(State.SERVING)
					RunService.Heartbeat:Wait()

					if self.state == State.SERVING then
						self:_serve(model)
					end

					return
				end
			end

			task.wait(SERVE_INTERVAL)
		end

		if box and box.Parent then
			box:Destroy()
		end
		self.serveBoxTask = nil
	end)
end

function NPC:_serve(ramenModel)
	local npcRoot = self.model.PrimaryPart
	local ramenRoot = ramenModel.PrimaryPart
	if not npcRoot or not ramenRoot then
		return
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = "FoodWeld"
	weld.Part0 = npcRoot
	weld.Part1 = ramenRoot
	weld.Parent = ramenRoot

	self.food = ramenModel
	self.foodWeld = weld

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
	if not root then
		self:Destroy()
		return
	end

	if self.food then
		self.food:Destroy()
		self.food = nil
	end
	self.foodWeld = nil

	local seatWeld = root:FindFirstChild("SeatWeld")
	if seatWeld then
		seatWeld:Destroy()
	end

	self.moving = false
	if self.humanoid then
		self.humanoid:MoveTo(self.humanoid.RootPart.Position)
		RunService.Heartbeat:Wait()
	end
	root.CFrame = self.hitbox.CFrame

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

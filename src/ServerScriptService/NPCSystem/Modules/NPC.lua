local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Utils = require(script.Parent.Utils)

local NPCSpawn = workspace:WaitForChild("NPCSystem"):WaitForChild("NPCSpawn")

local WAIT_FOOD_TIME = 120
local EAT_TIME = 2

local SERVE_BOX_SIZE = Vector3.new(2, 2, 3)
local SERVE_BOX_OFFSET = CFrame.new(0, -0.6, -2)
local SERVE_CLAIM_ATTR = "ServingNPC"
local SERVE_CLAIM_DIST_ATTR = "ServingNPCDist2"

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
local NEXT_ID = 0

local function reverseWaypointsSkipLast(waypoints)
	local reversed = {}
	for i = #waypoints - 1, 1, -1 do
		reversed[#reversed + 1] = waypoints[i]
	end
	return reversed
end

local function distanceSquared(a, b)
	local diff = a - b
	return diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z
end

local function clearServeClaim(model, npcId)
	if model and model.Parent and model:GetAttribute(SERVE_CLAIM_ATTR) == npcId then
		model:SetAttribute(SERVE_CLAIM_ATTR, nil)
		model:SetAttribute(SERVE_CLAIM_DIST_ATTR, nil)
	end
end

function NPC.new(context)
	local self = setmetatable({
		seat = context.seat,
		hitbox = context.hitbox,

		model = Utils:spawnModel(),
		humanoid = nil,

		enterWaypoints = nil,

		state = State.ENTERING,
		stateTimeLeft = 0,

		food = nil,
		claimedFood = nil,

		serveParams = nil,
	}, NPC)

	NEXT_ID += 1
	self.id = NEXT_ID

	if self.model then
		self.humanoid = self.model:FindFirstChildOfClass("Humanoid")
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {
			self.model,
			self.seat,
		}
		self.serveParams = params
	end

	self:_enterShop()

	return self
end

function NPC:_setState(newState, time)
	if self.state == State.DEAD then
		return
	end
	if self.state == newState then
		if time ~= nil then
			self.stateTimeLeft = time
		end
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

function NPC:TickCountdown()
	if self.state == State.DEAD then
		return
	end

	if self.stateTimeLeft > 0 then
		if self.humanoid then
			self.humanoid.DisplayName = string.format("%s (%ds)", self.state, self.stateTimeLeft)
		end
		self.stateTimeLeft -= 1
	elseif self.state == State.WAITING_FOOD or self.state == State.EATING then
		self:_setState(State.LEAVING)
	end
end

function NPC:_computePath(startPos, goalPos)
	local path = PathfindingService:CreatePath(PATH_PARAMS)
	path:ComputeAsync(startPos, goalPos)
	if path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	return path:GetWaypoints()
end

function NPC:_followWaypoints(waypoints, activeState, onSuccess)
	local expectedState = activeState
	task.spawn(function()
		for _, wp in ipairs(waypoints) do
			if self.state ~= expectedState then
				return
			end
			if not self.humanoid or not self.humanoid.Parent then
				return
			end

			self.humanoid:MoveTo(wp.Position)
			if not self.humanoid.MoveToFinished:Wait() then
				return
			end
		end

		if self.state ~= expectedState then
			return
		end
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
	self:_followWaypoints(waypoints, State.ENTERING, function()
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
	weld.C0 = CFrame.new(0, -5, 0)
	weld.Parent = root

	if self.humanoid then
		self.humanoid.Sit = true
	end

	self:_setState(State.WAITING_FOOD, WAIT_FOOD_TIME)
end

function NPC:TryServe()
	if self.state ~= State.WAITING_FOOD then
		return
	end

	local primary = self.model and self.model.PrimaryPart
	if not primary or not self.serveParams then
		return
	end

	local boxCFrame = primary.CFrame * SERVE_BOX_OFFSET
	local parts = workspace:GetPartBoundsInBox(boxCFrame, SERVE_BOX_SIZE, self.serveParams)

	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if
			model
			and CollectionService:HasTag(model, "Ramen")
			and model:GetAttribute("Completed") == true
			and model:GetAttribute("BeingDragged") ~= true
		then
			local ramenRoot = model.PrimaryPart
			if not ramenRoot or ramenRoot:FindFirstChild("FoodWeld") then
				continue
			end

			local dist2 = distanceSquared(primary.Position, ramenRoot.Position)
			local currentClaim = model:GetAttribute(SERVE_CLAIM_ATTR)
			local currentDist = model:GetAttribute(SERVE_CLAIM_DIST_ATTR)
			if currentClaim ~= nil and currentClaim ~= self.id and currentDist ~= nil and dist2 >= currentDist then
				continue
			end

			model:SetAttribute(SERVE_CLAIM_ATTR, self.id)
			model:SetAttribute(SERVE_CLAIM_DIST_ATTR, dist2)
			self.claimedFood = model

			self:_setState(State.SERVING)
			task.spawn(function()
				RunService.Heartbeat:Wait()
				if self.state ~= State.SERVING or model:GetAttribute(SERVE_CLAIM_ATTR) ~= self.id then
					clearServeClaim(model, self.id)
					self.claimedFood = nil
					if self.state == State.SERVING then
						self:_setState(State.WAITING_FOOD, WAIT_FOOD_TIME)
					end
					return
				end

				self:_serve(model)
			end)
			return
		end
	end
end

function NPC:_serve(ramenModel)
	local npcRoot = self.model.PrimaryPart
	local ramenRoot = ramenModel.PrimaryPart
	if not npcRoot or not ramenRoot then
		return
	end
	if ramenRoot:FindFirstChild("FoodWeld") then
		return
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = "FoodWeld"
	weld.Part0 = npcRoot
	weld.Part1 = ramenRoot
	weld.Parent = ramenRoot

	self.food = ramenModel
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
	end

	local seatWeld = root:FindFirstChild("SeatWeld")
	if seatWeld then
		seatWeld:Destroy()
	end

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
	self:_followWaypoints(back, State.LEAVING, function()
		self:Destroy()
	end)
end

function NPC:Destroy()
	self.state = State.DEAD

	clearServeClaim(self.claimedFood, self.id)
	self.claimedFood = nil

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

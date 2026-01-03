local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SimplePath = require(ReplicatedStorage.Packages.SimplePath)

local NPCFolder = ReplicatedStorage:WaitForChild("NPCs")
local NPCSpawn = workspace:WaitForChild("NPCSystem"):WaitForChild("NPCSpawn")
local NPCContainer = workspace:WaitForChild("NPCs")

local LEAVE_TIME = 2

local PATH_PARAMS = {
	AgentRadius = 3,
	AgentHeight = 5,
	AgentCanJump = true,
}

local NPC = {}
NPC.__index = NPC

local function spawnModel()
	local rig = NPCFolder:WaitForChild("Rig")
	local model = rig:Clone()
	model.Parent = NPCContainer
	return model
end

function NPC.new(context)
	local self = setmetatable({
		seat = context.seat,
		hitbox = context.hitbox,
		model = spawnModel(),
		path = nil,
		seated = false,
	}, NPC)

	self.model:SetPrimaryPartCFrame(NPCSpawn.CFrame)
	self:_enterShop()

	return self
end

function NPC:_createPath(onReached)
	if self.path then
		self.path:Destroy()
		self.path = nil
	end

	local path = SimplePath.new(self.model, PATH_PARAMS)
	path.Visualize = true

	path.Reached:Once(function()
		if onReached then
			onReached()
		end
	end)

	path.Blocked:Connect(function()
		path:Run(path.Target)
	end)

	self.path = path
	return path
end

function NPC:_moveTo(goal, onReached)
	local path = self:_createPath(onReached)
	path:Run(goal)
end

function NPC:_enterShop()
	self:_moveTo(self.hitbox.Position, function()
		if self.seated then
			return
		end
		self.seated = true

		local weld = Instance.new("Motor6D")
		weld.Name = "SeatWeld"
		weld.Part0 = self.seat
		weld.Part1 = self.model.PrimaryPart
		weld.C0 = CFrame.new(0, 3, 0)
		weld.Parent = self.model.PrimaryPart

		local humanoid = self.model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Sit = true
		end

		task.delay(LEAVE_TIME, function()
			if self.model then
				self:startLeaving()
			end
		end)
	end)
end

function NPC:startLeaving()
	local root = self.model.PrimaryPart
	if not root then
		return
	end

	local weld = root:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end

	local humanoid = self.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = false
	end

	root.CFrame = self.hitbox.CFrame

	self:_moveTo(NPCSpawn.Position, function()
		self:Destroy()
	end)
end

function NPC:Destroy()
	if self.path then
		self.path:Destroy()
		self.path = nil
	end

	if self.model then
		self.model:Destroy()
		self.model = nil
	end

	setmetatable(self, nil)
end

return NPC

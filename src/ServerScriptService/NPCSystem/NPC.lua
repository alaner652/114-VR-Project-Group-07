local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local NPCFolder = ReplicatedStorage:WaitForChild("NPCs")
local NPCSpawn = workspace:WaitForChild("NPCSystem"):WaitForChild("NPCSpawn")

local LEAVE_TIME = 5
local AGENT_RADIUS = 3
local AGENT_HEIGHT = 5

local ENTRY_PATH_CACHE = {}

local NPC = {}
NPC.__index = NPC

local function spawnModel()
	local rig = NPCFolder:FindFirstChild("Rig")
	if not rig then
		return nil
	end
	local model = rig:Clone()
	model.Parent = workspace:WaitForChild("NPCs")
	return model
end

local function computePath(fromPos, toPos)
	local path = PathfindingService:CreatePath({
		AgentRadius = AGENT_RADIUS,
		AgentHeight = AGENT_HEIGHT,
		AgentCanJump = false,
	})

	path:ComputeAsync(fromPos, toPos)
	if path.Status ~= Enum.PathStatus.Success then
		return nil
	end

	local points = {}
	for _, wp in ipairs(path:GetWaypoints()) do
		table.insert(points, wp.Position)
	end
	return points
end

function NPC.new(context)
	local self = setmetatable({}, NPC)

	self.seat = context.seat
	self.hitbox = context.hitbox
	self.events = context.events

	self.model = spawnModel()
	if not self.model or not self.model.PrimaryPart then
		return self
	end

	self.model:SetPrimaryPartCFrame(NPCSpawn.CFrame)
	RunService.Heartbeat:Wait()

	-- ⭐ Entry path cache（依 hitbox）
	if ENTRY_PATH_CACHE[self.hitbox] then
		self.entryPath = ENTRY_PATH_CACHE[self.hitbox]
	else
		self.entryPath = computePath(self.model.PrimaryPart.Position, self.hitbox.Position)
		ENTRY_PATH_CACHE[self.hitbox] = self.entryPath
	end

	self:_enterShop()
	return self
end

function NPC:_moveTo(pos)
	local humanoid = self.model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end
	humanoid:MoveTo(pos)
	return humanoid.MoveToFinished:Wait()
end

function NPC:_walkPathWithReplan(path, finalTarget)
	for _, pos in ipairs(path) do
		if self.destroyed then
			return false
		end

		if not self:_moveTo(pos) then
			local replanned = computePath(self.model.PrimaryPart.Position, finalTarget)
			if replanned then
				return self:_walkPathWithReplan(replanned, finalTarget)
			end
			return false
		end
	end
	return true
end

function NPC:_enterShop()
	self.seat:SetAttribute("Active", true)

	task.spawn(function()
		if self.entryPath then
			self:_walkPathWithReplan(self.entryPath, self.hitbox.Position)
		end
	end)

	local conn
	conn = self.hitbox.Touched:Connect(function(part)
		if not part:IsDescendantOf(self.model) or self.seated then
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
			self:startLeaving()
		end)

		conn:Disconnect()
	end)
end

function NPC:startLeaving()
	if self.isLeaving or self.destroyed then
		return
	end
	self.isLeaving = true
	if self.events then
		self.events.emit("NPCStartedLeaving")
	end

	local humanoid = self.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Sit = false
	end

	local weld = self.model.PrimaryPart:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end

	self.model:SetPrimaryPartCFrame(self.hitbox.CFrame * CFrame.new(0, 0, -2))

	if self.entryPath and #self.entryPath >= 2 then
		local reverse = {}
		for i = #self.entryPath - 1, 1, -1 do
			table.insert(reverse, self.entryPath[i])
		end

		if self:_walkPathWithReplan(reverse, NPCSpawn.Position) then
			self:Destroy()
			return
		end
	end

	local fallback = computePath(self.model.PrimaryPart.Position, NPCSpawn.Position)
	if fallback then
		self:_walkPathWithReplan(fallback, NPCSpawn.Position)
	end

	self:Destroy()
end

function NPC:Destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true

	if self.seat then
		self.seat:SetAttribute("Active", false)
	end

	if self.model then
		self.model:Destroy()
	end

	if self.events then
		self.events.emit("NPCFinishedLeaving")
	end
end

return NPC

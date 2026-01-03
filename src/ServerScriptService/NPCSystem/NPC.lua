local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NPCFolder = ReplicatedStorage:WaitForChild("NPCs")

local LEAVE_TIME = 120 -- 秒

local NPC = {}
NPC.__index = NPC

--------------------------------------------------
-- Spawn NPC Model
--------------------------------------------------
local function spawnModel()
	local model = NPCFolder:FindFirstChild("Rig")
	if not model then
		warn("NPC model not found.")
		return nil
	end

	local cloned = model:Clone()
	cloned.Parent = workspace.NPCs
	return cloned
end

--------------------------------------------------
-- Constructor
--------------------------------------------------
function NPC.new(context)
	local self = setmetatable({}, NPC)

	self.seat = context.seat
	self.hitbox = context.hitbox
	self.events = context.events
	self.model = spawnModel()

	self:start()
	return self
end

--------------------------------------------------
-- Start / Move to Seat
--------------------------------------------------
function NPC:start()
	if not self.model or not self.model.PrimaryPart then
		warn("NPC model has no PrimaryPart")
		return
	end

	self.model:SetPrimaryPartCFrame(workspace.NPCSpawn.CFrame + Vector3.new(0, 0, -5))

	local humanoid = self.model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	self.seat:SetAttribute("Active", true)
	humanoid:MoveTo(self.hitbox.Position)

	local conn
	conn = self.hitbox.Touched:Connect(function(part)
		if not part:IsDescendantOf(self.model) then
			return
		end
		if self.seated then
			return
		end
		self.seated = true

		local weld = Instance.new("Motor6D")
		weld.Name = "SeatWeld"
		weld.Part0 = self.seat
		weld.Part1 = self.model.PrimaryPart
		weld.C0 = CFrame.new(0, 2, 0)
		weld.Parent = self.model.PrimaryPart

		self:_startWaitingTimer()
		conn:Disconnect()
	end)
end

--------------------------------------------------
-- Countdown Display (每秒更新名字)
--------------------------------------------------
function NPC:_updateCountdownDisplay(seconds)
	if not self.model then
		return
	end

	self.model.Name = tostring(seconds)
end

--------------------------------------------------
-- Waiting Timer (逐秒倒數)
--------------------------------------------------
function NPC:_startWaitingTimer()
	if self.waiting then
		return
	end
	self.waiting = true

	task.spawn(function()
		local remaining = LEAVE_TIME

		while remaining > 0 do
			if self.isLeaving or self.destroyed then
				return
			end

			self:_updateCountdownDisplay(remaining)

			task.wait(1)
			remaining -= 1
		end

		-- 顯示 0
		self:_updateCountdownDisplay(0)

		if not self.isLeaving and not self.destroyed then
			self:startLeaving()
		end
	end)
end

--------------------------------------------------
-- Start Leaving
--------------------------------------------------
function NPC:startLeaving()
	if self.isLeaving then
		return
	end
	self.isLeaving = true

	if self.events then
		self.events.emit("NPCStartedLeaving")
	end

	local humanoid = self.model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local weld = self.model.PrimaryPart:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end

	humanoid:MoveTo(workspace.NPCSpawn.Position)

	local conn
	conn = humanoid.MoveToFinished:Connect(function()
		conn:Disconnect()

		if self.events then
			self.events.emit("NPCFinishedLeaving")
		end

		self:Destroy()
	end)
end

--------------------------------------------------
-- Destroy NPC
--------------------------------------------------
function NPC:Destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true

	self.seat:SetAttribute("Active", false)

	if self.model then
		self.model:Destroy()
	end
end

return NPC

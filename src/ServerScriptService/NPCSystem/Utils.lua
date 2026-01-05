-- NPC rig helpers: spawn, appearance, and humanoid setup.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCFolder = ReplicatedStorage:WaitForChild("NPCs")
local NPCSpawn = workspace:WaitForChild("NPCSystem"):WaitForChild("NPCSpawn")
local NPCContainer = workspace:WaitForChild("NPCs")

local Utils = {}

local DISABLED_STATES = {
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.GettingUp,
}

local function configureHumanoid(humanoid)
	-- Normalize humanoid state for NPCs.
	for _, state in ipairs(DISABLED_STATES) do
		humanoid:SetStateEnabled(state, false)
	end

	if not humanoid.Sit then
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end
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
			configureHumanoid(humanoid)
		end
	end)
end

function Utils:spawnModel()
	local rig = NPCFolder:WaitForChild("Rig")
	local model = rig:Clone()

	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		model.Parent = NPCContainer
		model:SetPrimaryPartCFrame(NPCSpawn.CFrame)

		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
			configureHumanoid(humanoid)
			applyRandomFriendAppearance(humanoid)
		end
	end

	return model
end

return Utils

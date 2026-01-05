-- NPC rig helpers: spawn, appearance, and humanoid setup.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local warned = {}

local function warnOnce(key, msg)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(msg)
end

local function getNpcFolder()
	return ReplicatedStorage:FindFirstChild("NPCs")
end

local function getNpcSpawn()
	local npcSystem = workspace:FindFirstChild("NPCSystem")
	return npcSystem and npcSystem:FindFirstChild("NPCSpawn") or nil
end

local function getNpcContainer()
	local container = workspace:FindFirstChild("NPCs")
	if not container then
		container = Instance.new("Folder")
		container.Name = "NPCs"
		container.Parent = workspace
	end
	return container
end

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
	local npcFolder = getNpcFolder()
	if not npcFolder then
		warnOnce("npcFolder", "[NPCSystem] Missing ReplicatedStorage.NPCs")
		return nil
	end

	local rig = npcFolder:FindFirstChild("Rig")
	if not rig then
		warnOnce("npcRig", "[NPCSystem] Missing ReplicatedStorage.NPCs.Rig")
		return nil
	end

	local npcSpawn = getNpcSpawn()
	if not npcSpawn then
		warnOnce("npcSpawn", "[NPCSystem] Missing workspace.NPCSystem.NPCSpawn")
		return nil
	end

	local model = rig:Clone()

	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
	end

	if not model.PrimaryPart then
		warnOnce("npcPrimaryPart", "[NPCSystem] NPC rig missing PrimaryPart")
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		model.Parent = getNpcContainer()
		model:SetPrimaryPartCFrame(npcSpawn.CFrame)

		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		configureHumanoid(humanoid)
		applyRandomFriendAppearance(humanoid)
	end

	return model
end

return Utils

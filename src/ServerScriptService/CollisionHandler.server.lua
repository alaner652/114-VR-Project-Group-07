local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local COLLISION_GROUP = {
	Player = "Player",
	NPC = "NPC",
	Draggable = "Draggable",
	Default = "Default",
}

local trackedModels = {}

local function applyCollisionGroup(model: Model, groupName: string)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.CollisionGroup = groupName
		end
	end
end

local function untrackModel(model: Model)
	local info = trackedModels[model]
	if not info then
		return
	end

	if info.descConn then
		info.descConn:Disconnect()
	end
	if info.destroyConn then
		info.destroyConn:Disconnect()
	end

	trackedModels[model] = nil
end

local function trackModel(model: Model, groupName: string)
	applyCollisionGroup(model, groupName)

	local info = trackedModels[model]
	if info then
		info.groupName = groupName
		return
	end

	info = {
		groupName = groupName,
	}

	info.descConn = model.DescendantAdded:Connect(function(inst)
		if not inst:IsA("BasePart") then
			return
		end

		local current = trackedModels[model]
		if current then
			inst.CollisionGroup = current.groupName
		end
	end)

	info.destroyConn = model.Destroying:Connect(function()
		untrackModel(model)
	end)

	trackedModels[model] = info
end

local function findRootModel(inst: Instance): Model?
	return inst and inst:FindFirstAncestorOfClass("Model") or nil
end

local function setupPlayerCharacter(character: Model)
	trackModel(character, COLLISION_GROUP.Player)
end

local function bindPlayer(player: Player)
	if player.Character then
		setupPlayerCharacter(player.Character)
	end

	player.CharacterAdded:Connect(setupPlayerCharacter)
end

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayer(player)
end

Players.PlayerAdded:Connect(bindPlayer)

local NPC_FOLDER = workspace:WaitForChild("NPCs")

local function setupNPC(npcModel: Model)
	trackModel(npcModel, COLLISION_GROUP.NPC)
end

for _, npc in ipairs(NPC_FOLDER:GetChildren()) do
	if npc:IsA("Model") then
		setupNPC(npc)
	end
end

NPC_FOLDER.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		setupNPC(child)
	end
end)

local function onDraggableAdded(inst: Instance)
	local model = findRootModel(inst)
	if model then
		trackModel(model, COLLISION_GROUP.Draggable)
	end
end

local function onDraggableRemoved(inst: Instance)
	local model = findRootModel(inst)
	if model then
		applyCollisionGroup(model, COLLISION_GROUP.Default)
		untrackModel(model)
	end
end

for _, inst in ipairs(CollectionService:GetTagged("Draggable")) do
	onDraggableAdded(inst)
end

CollectionService:GetInstanceAddedSignal("Draggable"):Connect(onDraggableAdded)
CollectionService:GetInstanceRemovedSignal("Draggable"):Connect(onDraggableRemoved)

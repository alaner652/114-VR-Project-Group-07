local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local function setupCharacter(character: Model)
	for _, obj in ipairs(character:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.CollisionGroup = "Player"
		end
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		setupCharacter(player.Character)
	end
	player.CharacterAdded:Connect(setupCharacter)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(setupCharacter)
end)

local function getRootModel(instance: Instance): Model?
	if not instance then
		return nil
	end
	return instance:FindFirstAncestorOfClass("Model")
end

local function setCollisionGroupForModel(model: Model, groupName: string)
	if not model then
		return
	end

	--print("Setting collision group:", model.Name, "->", groupName)

	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.CollisionGroup = groupName
		end
	end
end

for _, inst in ipairs(CollectionService:GetTagged("Draggable")) do
	local model = getRootModel(inst)
	if model then
		setCollisionGroupForModel(model, "Draggable")
	end
end

CollectionService:GetInstanceAddedSignal("Draggable"):Connect(function(inst)
	local model = getRootModel(inst)
	if model then
		setCollisionGroupForModel(model, "Draggable")
	end
end)

CollectionService:GetInstanceRemovedSignal("Draggable"):Connect(function(inst)
	local model = getRootModel(inst)
	if model then
		setCollisionGroupForModel(model, "Default")
	end
end)

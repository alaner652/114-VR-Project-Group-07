local Players = game:GetService("Players")

local DragRequest = game.ReplicatedStorage:WaitForChild("DragRequest")
local GetDraggingObject = game.ServerScriptService:WaitForChild("GetDraggingObject")
local ReleaseDraggingObject = game.ServerScriptService:WaitForChild("ReleaseDraggingObject")

local PlayerDragging = {}

local function isBeingDraggedByOther(player, object)
	for p, dragged in pairs(PlayerDragging) do
		if p ~= player and dragged == object then
			return true
		end
	end
	return false
end

local function getRoot(instance)
	return instance:FindFirstAncestorOfClass("Model") or instance
end

local function setCollisionGroupFromPart(part, groupName)
	local root = getRoot(part)

	if root:IsA("BasePart") then
		root.CollisionGroup = groupName
	end

	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.CollisionGroup = groupName
		end
	end
end

DragRequest.OnServerInvoke = function(player: Player, object: BasePart, requestingPickup: boolean)
	local root: Model = getRoot(object)

	if requestingPickup then
		if not object then
			return false
		end
		if not object:IsDescendantOf(workspace) then
			return false
		end
		if PlayerDragging[player] then
			return false
		end
		if isBeingDraggedByOther(player, object) then
			return false
		end

		object:SetNetworkOwner(player)
		PlayerDragging[player] = object
		setCollisionGroupFromPart(object, "Draggable")
		root:SetAttribute("BeingDragged", true)

		return true
	end

	local current = PlayerDragging[player]
	if not current then
		return true
	end

	if current:IsDescendantOf(workspace) then
		current:SetNetworkOwner(nil)
		setCollisionGroupFromPart(current, "Default")
		root:SetAttribute("BeingDragged", false)
	end

	PlayerDragging[player] = nil
	return true
end

GetDraggingObject.OnInvoke = function(player: Player)
	return PlayerDragging[player]
end

ReleaseDraggingObject.OnInvoke = function(player: Player)
	local current = PlayerDragging[player]
	if not current then
		return
	end

	if current:IsDescendantOf(workspace) then
		current:SetNetworkOwner(nil)
		setCollisionGroupFromPart(current, "Default")
	end

	PlayerDragging[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	PlayerDragging[player] = nil
end)

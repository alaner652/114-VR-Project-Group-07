local Players = game:GetService("Players")

local DragRequest = game.ReplicatedStorage:WaitForChild("DragRequest")
local GetDraggingObject = game.ServerScriptService:WaitForChild("GetDraggingObject")
local ReleaseDraggingObject = game.ServerScriptService:WaitForChild("ReleaseDraggingObject")

local PlayerDragging = {}

local function getRoot(instance)
	if not instance then
		return nil
	end

	return instance:FindFirstAncestorOfClass("Model") or instance
end

local function setCollisionGroupForRoot(root, groupName)
	if not root then
		return
	end

	if root:IsA("BasePart") then
		root.CollisionGroup = groupName
	end

	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.CollisionGroup = groupName
		end
	end
end

local function stopDrag(player: Player)
	local current = PlayerDragging[player]
	if not current then
		return
	end

	local root = getRoot(current)

	if current:IsDescendantOf(workspace) and root then
		current:SetNetworkOwner(nil)
		setCollisionGroupForRoot(root, "Default")
		root:SetAttribute("BeingDragged", false)
	end

	PlayerDragging[player] = nil
end

local function startDrag(player: Player, object: BasePart)
	local root = getRoot(object)
	if not root then
		return false
	end

	if root:GetAttribute("BeingDragged") == true then
		return false
	end

	object:SetNetworkOwner(player)
	setCollisionGroupForRoot(root, "Draggable")
	root:SetAttribute("BeingDragged", true)
	PlayerDragging[player] = object

	return true
end

DragRequest.OnServerInvoke = function(player: Player, object: BasePart?, requestingPickup: boolean)
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

		return startDrag(player, object)
	end

	stopDrag(player)
	return true
end

GetDraggingObject.OnInvoke = function(player: Player)
	return PlayerDragging[player]
end

ReleaseDraggingObject.OnInvoke = function(player: Player)
	stopDrag(player)
end

Players.PlayerRemoving:Connect(function(player)
	stopDrag(player)
end)

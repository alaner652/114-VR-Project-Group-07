-- Server-side drag ownership and state tracking.
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

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

local function isRelated(a: Instance, b: Instance): boolean
	return a == b or a:IsDescendantOf(b) or b:IsDescendantOf(a)
end

local function getDraggingPlayerByObject(instance: Instance)
	for player, dragged in pairs(PlayerDragging) do
		if dragged and isRelated(instance, dragged) then
			return player
		end
	end
	return nil
end

local function stopDrag(player: Player)
	-- Clear network ownership and the BeingDragged flag.
	local current = PlayerDragging[player]
	if not current then
		return
	end

	local root = getRoot(current)

	if current:IsDescendantOf(workspace) and root then
		current:SetNetworkOwner(nil)
		root:SetAttribute("BeingDragged", false)
	end

	PlayerDragging[player] = nil
end

local function startDrag(player: Player, object: BasePart)
	-- Grant ownership if the object is not already dragged.
	local root = getRoot(object)
	if not root then
		return false
	end

	if root:GetAttribute("BeingDragged") == true then
		return false
	end

	object:SetNetworkOwner(player)
	root:SetAttribute("BeingDragged", true)
	PlayerDragging[player] = object

	return true
end

DragRequest.OnServerInvoke = function(player: Player, object: BasePart?, requestingPickup: boolean)
	--print("DragRequest received from", player.Name, "requestingPickup =", requestingPickup, "object =", object)
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

CollectionService:GetInstanceRemovedSignal("Draggable"):Connect(function(instance)
	local player = getDraggingPlayerByObject(instance)
	if player then
		print("Draggable removed from", instance.Name, "stopping drag for player", player and player.Name or "nil")
		stopDrag(player)
	end
end)

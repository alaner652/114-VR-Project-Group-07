-- Client-side drag controller: raycast, request server ownership, and drive attachments.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VRService = game:GetService("VRService")

local RAYCAST_DISTANCE = 8
local DEFAULT_DRAG_DISTANCE = 4
local MIN_DRAG_DISTANCE = 2
local MAX_DRAG_DISTANCE = RAYCAST_DISTANCE
local SCROLL_STEP = 0.5

local DragState = {
	Idle = 0,
	Hovering = 1,
	Dragging = 2,
}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local dragRemote = ReplicatedStorage:WaitForChild("DragRequest")
local ForcePickupRemote = ReplicatedStorage:WaitForChild("ForcePickup")

local dragTargetAttachment: Attachment = workspace.Terrain:WaitForChild("DragTarget")

local state = DragState.Idle
local target: Part?
local grabbedObject: Part?
local dragAttachment: Attachment?
local distance = DEFAULT_DRAG_DISTANCE

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function setDistance(value: number)
	distance = math.clamp(value, MIN_DRAG_DISTANCE, MAX_DRAG_DISTANCE)
end

local function updateRaycastFilter()
	if player.Character then
		rayParams.FilterDescendantsInstances = player.Character:GetDescendants()
	end
end

player.CharacterAdded:Connect(updateRaycastFilter)
updateRaycastFilter()

local function getRootModel(instance: Instance): Model?
	return instance and instance:FindFirstAncestorOfClass("Model") or nil
end

local function isBeingDragged(instance: Instance): boolean
	local model = getRootModel(instance)
	if not model then
		return false
	end

	return model:GetAttribute("BeingDragged") == true
end

local lastHighlighted: Instance?

local function setHighlight(object: Instance?)
	local model = object and getRootModel(object) or nil
	if lastHighlighted == model then
		return
	end

	script.Highlight.Adornee = model
	lastHighlighted = model
end

local function getOrCreateDragAttachment(part: Part?): Attachment?
	if not part or not part.Parent then
		return nil
	end

	local att = part:FindFirstChild("DragAttachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "DragAttachment"
		att.Parent = part
	end
	return att
end

local function dropObject()
	if not grabbedObject then
		return
	end

	dragRemote:InvokeServer(grabbedObject, false)

	grabbedObject = nil
	dragAttachment = nil
	state = DragState.Idle

	script.AlignOrientation.Attachment0 = nil
	script.AlignPosition.Attachment0 = nil
end

local function tryStartDrag(candidate: Part?): boolean
	if not candidate or not candidate.Parent then
		return false
	end

	if not dragRemote:InvokeServer(candidate, true) then
		return false
	end

	if not candidate.Parent then
		return false
	end

	grabbedObject = candidate
	dragAttachment = getOrCreateDragAttachment(candidate)
	if not dragAttachment then
		dropObject()
		return false
	end

	script.AlignOrientation.Attachment0 = dragAttachment
	script.AlignPosition.Attachment0 = dragAttachment
	state = DragState.Dragging
	return true
end

UserInputService.InputBegan:Connect(function(input, processed)
	-- Click to pick up or drop.
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	if state == DragState.Dragging then
		dropObject()
		return
	end

	if state == DragState.Hovering and target then
		tryStartDrag(target)
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end

	if state == DragState.Dragging and grabbedObject then
		local delta = input.Position.Z
		if delta ~= 0 then
			setDistance(distance + delta * SCROLL_STEP)
		end
	end
end)

ForcePickupRemote.OnClientEvent:Connect(function(object: Part)
	-- Server can force a pickup (e.g., after spawning an item).
	if state == DragState.Dragging then
		dropObject()
		return
	end
	if tryStartDrag(object) then
		setHighlight(object)
	end
end)

local function getBaseCFrame(): CFrame
	if UserInputService.VREnabled then
		return camera.CFrame * VRService:GetUserCFrame(Enum.UserCFrame.RightHand)
	end
	return camera.CFrame
end

local function updateDragTargetAttachment(baseCF: CFrame)
	dragTargetAttachment.WorldCFrame = baseCF * CFrame.new(0, 0, -distance)
end

RunService.RenderStepped:Connect(function()
	-- Update drag target and highlight each frame.
	local baseCF = getBaseCFrame()
	if state == DragState.Dragging and grabbedObject then
		updateDragTargetAttachment(baseCF)
		return
	end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local result = workspace:Raycast(ray.Origin, ray.Direction * RAYCAST_DISTANCE, rayParams)
	local hit = result and result.Instance

	if hit and hit:HasTag("Draggable") and not isBeingDragged(hit) then
		target = hit
		state = DragState.Hovering
		setDistance((ray.Origin - result.Position).Magnitude)
	else
		target = nil
		state = DragState.Idle
		setDistance(DEFAULT_DRAG_DISTANCE)
	end

	updateDragTargetAttachment(baseCF)
	setHighlight(target)
end)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VRService = game:GetService("VRService")

local MAX_DISTANCE = 10
local MIN_DISTANCE = 4
local LIMIT_DISTANCE = true

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
local distance = MIN_DISTANCE

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateRaycastFilter()
	if player.Character then
		rayParams.FilterDescendantsInstances = player.Character:GetDescendants()
	end
end

player.CharacterAdded:Connect(updateRaycastFilter)
updateRaycastFilter()

local function getRootModel(instance: Instance): Model?
	if not instance then
		return nil
	end
	return instance:FindFirstAncestorOfClass("Model")
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
	if not object then
		script.Highlight.Adornee = nil
		lastHighlighted = nil
		return
	end

	local model = getRootModel(object)
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

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	if state == DragState.Dragging then
		dropObject()
		return
	end

	if state ~= DragState.Hovering or not target then
		return
	end

	local candidate = target
	if dragRemote:InvokeServer(candidate, true) then
		if not candidate or not candidate.Parent then
			return
		end

		grabbedObject = candidate
		dragAttachment = getOrCreateDragAttachment(grabbedObject)
		if not dragAttachment then
			dropObject()
			return
		end

		script.AlignOrientation.Attachment0 = dragAttachment
		script.AlignPosition.Attachment0 = dragAttachment

		state = DragState.Dragging
	end
end)

ForcePickupRemote.OnClientEvent:Connect(function(object: Part)
	if state == DragState.Dragging then
		dropObject()
		return
	end
	local candidate = object
	if dragRemote:InvokeServer(candidate, true) then
		print("Server approved force pickup")
		if not candidate or not candidate.Parent then
			return
		end

		grabbedObject = candidate
		dragAttachment = getOrCreateDragAttachment(grabbedObject)
		if not dragAttachment then
			dropObject()
			return
		end

		script.AlignOrientation.Attachment0 = dragAttachment
		script.AlignPosition.Attachment0 = dragAttachment

		state = DragState.Dragging
		setHighlight(candidate)
	end
end)

local function getBaseCFrame(): CFrame
	if UserInputService.VREnabled then
		return camera.CFrame * VRService:GetUserCFrame(Enum.UserCFrame.RightHand)
	end
	return camera.CFrame
end

RunService.RenderStepped:Connect(function()
	if state == DragState.Dragging and grabbedObject then
		local baseCF = getBaseCFrame()
		dragTargetAttachment.WorldCFrame = baseCF * CFrame.new(0, 0, -distance)
		return
	end

	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_DISTANCE, rayParams)

	if result and result.Instance and result.Instance:HasTag("Draggable") then
		print("Raycast result:", result.Instance)
		if isBeingDragged(result.Instance) then
			target = nil
			state = DragState.Idle
		else
			target = result.Instance
			state = DragState.Hovering

			if not LIMIT_DISTANCE then
				distance = (ray.Origin - result.Position).Magnitude
			else
				distance = MIN_DISTANCE
			end
		end
	else
		target = nil
		state = DragState.Idle
	end

	setHighlight(target)
end)

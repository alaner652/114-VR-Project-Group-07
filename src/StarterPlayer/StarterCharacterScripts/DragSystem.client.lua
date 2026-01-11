-- Client Drag Controller (Overlap + Ray-direction selection)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VRService = game:GetService("VRService")
local CollectionService = game:GetService("CollectionService")

-- ===== Constants =====
local DEFAULT_DISTANCE = 4
local MIN_DISTANCE = 2
local MAX_DISTANCE = 8
local SCROLL_STEP = 0.5
local OVERLAP_RADIUS = 2

-- ===== Drag State =====
local DragState = {
	Idle = 0,
	Hovering = 1,
	Dragging = 2,
}

-- ===== Services / Remotes =====
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local DragRequest = ReplicatedStorage:WaitForChild("DragRequest")
local ForcePickupRemote = ReplicatedStorage:WaitForChild("ForcePickup")

local dragTarget: Attachment = workspace.Terrain:WaitForChild("DragTarget")

-- ===== State =====
local state = DragState.Idle
local target: BasePart?
local grabbed: BasePart?
local distance = DEFAULT_DISTANCE

-- ===== Utils =====
local function clampDistance(v)
	distance = math.clamp(v, MIN_DISTANCE, MAX_DISTANCE)
end

local function rootModel(inst)
	return inst and inst:FindFirstAncestorOfClass("Model")
end

local function isBeingDragged(inst)
	local model = rootModel(inst)
	return model and model:GetAttribute("BeingDragged") == true
end

local lastHighlight: Model?
local function setHighlight(inst)
	local model = inst and rootModel(inst)
	if model == lastHighlight then
		return
	end
	script.Highlight.Adornee = model
	lastHighlight = model
end

local function getOrCreateAttachment(part)
	local att = part:FindFirstChild("DragAttachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "DragAttachment"
		att.Parent = part
	end
	return att
end

-- ===== Drag Control =====
local function drop()
	if not grabbed then
		return
	end
	DragRequest:InvokeServer(grabbed, false)
	grabbed = nil
	state = DragState.Idle
	script.AlignPosition.Attachment0 = nil
	script.AlignOrientation.Attachment0 = nil
end

local function tryDrag(part)
	if not part or not part.Parent then
		return false
	end
	if not DragRequest:InvokeServer(part, true) then
		return false
	end

	grabbed = part
	local att = getOrCreateAttachment(part)
	script.AlignPosition.Attachment0 = att
	script.AlignOrientation.Attachment0 = att
	state = DragState.Dragging
	return true
end

-- ===== Input =====
UserInputService.InputBegan:Connect(function(input, gp)
	if gp or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	if state == DragState.Dragging then
		drop()
	elseif state == DragState.Hovering and target then
		tryDrag(target)
	end
end)

UserInputService.InputChanged:Connect(function(input, gp)
	if gp or input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end
	if state == DragState.Dragging then
		clampDistance(distance + input.Position.Z * SCROLL_STEP)
	end
end)

ForcePickupRemote.OnClientEvent:Connect(function(part)
	if state == DragState.Dragging then
		drop()
	end
	if tryDrag(part) then
		setHighlight(part)
	end
end)

-- ===== Camera / Target =====
local function baseCFrame()
	if UserInputService.VREnabled then
		return camera.CFrame * VRService:GetUserCFrame(Enum.UserCFrame.RightHand)
	end
	return camera.CFrame
end

local function updateTarget(cf)
	dragTarget.WorldCFrame = cf * CFrame.new(0, 0, -distance)
end

-- ===== Main Loop =====
RunService.RenderStepped:Connect(function()
	local cf = baseCFrame()
	updateTarget(cf)

	if state == DragState.Dragging then
		return
	end

	local focusPos = cf.Position + cf.LookVector * distance

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Whitelist
	params.FilterDescendantsInstances = CollectionService:GetTagged("Draggable")

	local parts = workspace:GetPartBoundsInRadius(focusPos, OVERLAP_RADIUS, params)

	local rayDir = cf.LookVector
	local origin = cf.Position

	local best, bestScore

	for _, part in ipairs(parts) do
		if not isBeingDragged(part) then
			local toPart = part.Position - origin
			local forward = toPart:Dot(rayDir)
			if forward > 0 then
				local lateral = (toPart - rayDir * forward).Magnitude
				local score = forward - lateral * 1.5
				if not bestScore or score > bestScore then
					best = part
					bestScore = score
				end
			end
		end
	end

	if best then
		target = best
		state = DragState.Hovering
	else
		target = nil
		state = DragState.Idle
	end

	setHighlight(target)
end)

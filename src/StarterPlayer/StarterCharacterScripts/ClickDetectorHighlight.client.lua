-- Highlight models under the cursor that have a ClickDetector.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local highlight = script:WaitForChild("Highlight")

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function updateRaycastFilter()
	if player.Character then
		rayParams.FilterDescendantsInstances = player.Character:GetDescendants()
	end
end

player.CharacterAdded:Connect(updateRaycastFilter)
updateRaycastFilter()

local function getClickableModel(instance: Instance): Model?
	if not instance then
		return nil
	end

	local model = instance:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end

	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("ClickDetector") then
			return model
		end
	end

	return nil
end

local lastHighlighted: Model?

local function setHighlight(model: Model?)
	if not model then
		highlight.Adornee = nil
		lastHighlighted = nil
		return
	end

	if lastHighlighted == model then
		return
	end

	highlight.Adornee = model
	lastHighlighted = model
end

RunService.RenderStepped:Connect(function()
	-- Raycast from the mouse and update the highlight target.
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local result = workspace:Raycast(ray.Origin, ray.Direction * 10, rayParams)

	if result and result.Instance then
		local model = getClickableModel(result.Instance)
		setHighlight(model)
	else
		setHighlight(nil)
	end
end)

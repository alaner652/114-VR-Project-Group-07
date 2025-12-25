local Players = game:GetService("Players")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid")

	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5

	humanoid.AutoRotate = true

	camera.CameraType = Enum.CameraType.Custom
end

if player.Character then
	onCharacterAdded(player.Character)
end

player.CharacterAdded:Connect(onCharacterAdded)

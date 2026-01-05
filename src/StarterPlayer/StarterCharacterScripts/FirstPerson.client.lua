-- Forces first-person camera and keeps the body hidden.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

player.CameraMode = Enum.CameraMode.LockFirstPerson
humanoid.CameraOffset = Vector3.new(0, 0, -1)

task.wait()

-- Keep body parts transparent so they do not block the view.
for _, BasePart in pairs(character:GetChildren()) do
	if BasePart:IsA("BasePart") and BasePart.Name ~= "Head" then
		BasePart:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
			BasePart.LocalTransparencyModifier = BasePart.Transparency
		end)

		BasePart.LocalTransparencyModifier = BasePart.Transparency
	end
end

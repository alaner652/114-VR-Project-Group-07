-- Disable unwanted humanoid states for this experience.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")

local DISABLED_STATES = {
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.Ragdoll,
}

humanoid.JumpHeight = 0.1

for _, state in ipairs(DISABLED_STATES) do
	humanoid:SetStateEnabled(state, false)
end

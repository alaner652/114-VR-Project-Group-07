local Players = game:GetService("Players")

local function setupCharacter(character: Model)
	for _, obj in ipairs(character:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.CollisionGroup = "Player"
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(character)
	end)
end)

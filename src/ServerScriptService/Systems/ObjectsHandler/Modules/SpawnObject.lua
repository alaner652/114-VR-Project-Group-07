-- Spawn ingredients on click and hand them to the player.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ForcePickupRemote = ReplicatedStorage:WaitForChild("ForcePickup")

local Spawn = {}
Spawn.__index = Spawn

function Spawn.new(Model: BasePart)
	local self = setmetatable({
		model = Model,
		connection = nil,
	}, Spawn)

	self:_init()
	return self
end

function Spawn:_init()
	-- Create a ClickDetector for spawning.
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 10
	clickDetector.Parent = self.model

	self.connection = clickDetector.MouseClick:Connect(function(player)
		local spawnObjectName = self.model:GetAttribute("SpawnObject")
		if not spawnObjectName then
			warn("SpawnObject attribute not set on model:", self.model.Name)
			return
		end

		local ingredient = ReplicatedStorage.Ingredients:FindFirstChild(spawnObjectName)
		if not ingredient then
			warn("Ingredient not found in ReplicatedStorage.Ingredients:", spawnObjectName)
			return
		end

		local character = player.Character
		if not character then
			warn("Player character not found for player:", player.Name)
			return
		end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then
			warn("HumanoidRootPart not found in character for player:", player.Name)
			return
		end

		local newObject = ingredient:Clone()
		newObject.Parent = workspace.SpawnedObjects

		task.wait(0.2) -- Wait a frame to ensure the object is properly parented.

		local targetPos = hrp.Position + hrp.CFrame.LookVector * 3 + Vector3.new(0, 1, 0)
		local targetCF = CFrame.new(targetPos)

		if newObject.PrimaryPart then
			newObject:SetPrimaryPartCFrame(targetCF)
		else
			newObject:PivotTo(targetCF)
		end

		ForcePickupRemote:FireClient(player, newObject.PrimaryPart)
		print("Spawned object", spawnObjectName, "for player", player.Name)
	end)
end

function Spawn:Destroy()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	self.model = nil
end

return Spawn

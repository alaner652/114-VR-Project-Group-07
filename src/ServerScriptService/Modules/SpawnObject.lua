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
	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 10
	clickDetector.Parent = self.model

	self.connection = clickDetector.MouseClick:Connect(function()
		local spawnObjectName = self.model:GetAttribute("SpawnObject")
		if not spawnObjectName then
			return
		end

		local ingredient = game.ServerStorage.Ingredients:FindFirstChild(spawnObjectName)
		if not ingredient then
			return
		end

		local newObject = ingredient:Clone()
		newObject.Parent = workspace.SpawnedObjects

		if newObject.PrimaryPart then
			newObject:SetPrimaryPartCFrame(self.model.PrimaryPart.CFrame)
		end
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

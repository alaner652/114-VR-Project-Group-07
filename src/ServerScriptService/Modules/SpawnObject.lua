local CollectionService = game:GetService("CollectionService")

local Spawn = {}
Spawn.__index = Spawn

local function preparePhysics(model: Instance)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = false
			inst.CanCollide = true
			inst.AssemblyLinearVelocity = Vector3.zero
			inst.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

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

	self.connection = clickDetector.MouseClick:Connect(function(player)
		local spawnObjectName = self.model:GetAttribute("SpawnObject")
		if not spawnObjectName then
			return
		end

		local ingredient = game.ServerStorage.Ingredients:FindFirstChild(spawnObjectName)
		if not ingredient then
			return
		end

		local character = player.Character
		if not character then
			return
		end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then
			return
		end

		local newObject = ingredient:Clone()
		newObject:SetAttribute("BeingDragged", false)
		preparePhysics(newObject)

		local targetPos = hrp.Position + hrp.CFrame.LookVector * 3 + Vector3.new(0, 1, 0)
		local targetCF = CFrame.new(targetPos)

		if newObject.PrimaryPart then
			newObject:SetPrimaryPartCFrame(targetCF)
		else
			newObject:PivotTo(targetCF)
		end

		newObject.Parent = workspace.SpawnedObjects

		for _, tag in ipairs(CollectionService:GetTags(ingredient)) do
			CollectionService:AddTag(newObject, tag)
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

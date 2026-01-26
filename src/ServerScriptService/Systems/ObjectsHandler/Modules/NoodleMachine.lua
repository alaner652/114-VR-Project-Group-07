local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Ingredients = ReplicatedStorage:WaitForChild("Ingredients")

local Bindables = ServerScriptService:WaitForChild("Bindables")
local GetDraggingObject = Bindables:WaitForChild("GetDraggingObject")

local NoodleMachine = {}
NoodleMachine.__index = NoodleMachine

function NoodleMachine.new(model: Model)
	local self = setmetatable({
		model = model,
		prompt = nil,
		connection = nil,
	}, NoodleMachine)

	self:_init()
	return self
end

function NoodleMachine:_init()
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = self.model.Name
	prompt.MaxActivationDistance = 5
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = false
	prompt.HoldDuration = 0

	prompt.Parent = self.model.PrimaryPart

	self.connection = prompt.Triggered:Connect(function(player)
		local dragged = GetDraggingObject:Invoke(player)

		if not dragged then
			return
		end

		local ingredient = dragged:FindFirstAncestorOfClass("Model")
		if not ingredient then
			return
		end

		if ingredient.Name == "Dough" then
			if ingredient:GetAttribute("Active") ~= true then
				return
			end

			local oldCF = ingredient.PrimaryPart.CFrame

			local newNoodles = Ingredients:FindFirstChild("Noodles"):Clone()
			newNoodles.Parent = workspace.SpawnedObjects

			newNoodles:SetPrimaryPartCFrame(oldCF * CFrame.new(0, 1, 0))
			ingredient:Destroy()
		end
	end)
end

return NoodleMachine

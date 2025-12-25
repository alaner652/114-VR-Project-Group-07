local CollectionService = game:GetService("CollectionService")
local GetDraggingObject = game.ServerScriptService.GetDraggingObject
local SetToolState = game.ServerScriptService.SetToolState

function Init(tool: Model)
	if not tool:IsA("Model") then return end

	if tool.Name == "Soup Pot" then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ObjectText = tool.Name
		prompt.MaxActivationDistance = 10
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.UIOffset = Vector2.new(5, 0)
		prompt.Parent = tool.PrimaryPart

		prompt.Triggered:Connect(function(player)
			local draggedPart = GetDraggingObject:Invoke(player)
			if not draggedPart then return end

			local ingredientModel: Model = draggedPart:FindFirstAncestorOfClass("Model")
			if not ingredientModel then return end

			if ingredientModel.Name == "Soup" then
				SetToolState:Invoke(ingredientModel, true)
			end
		end)
	end
end

for _, tool in ipairs(CollectionService:GetTagged("Machine")) do
	Init(tool)
end

CollectionService:GetInstanceAddedSignal("Machine"):Connect(function(tool)
	Init(tool)
end)
local CollectionService = game:GetService("CollectionService")

local GetDraggingObject = game.ServerScriptService.GetDraggingObject
local ReleaseDraggingObject = game.ServerScriptService.ReleaseDraggingObject
local SetToolState = game.ServerScriptService.SetToolState

local FoodState = {}

--------------------------------------------------
-- Visual helpers
--------------------------------------------------
local function hide(model, record)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			record[part] = part.Transparency
			part.Transparency = 1
			part.CanCollide = false
		end
	end
end

local function restore(model, record)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local original = record[part]
			if original ~= nil then
				part.Transparency = original
				part.CanCollide = true
			end
		end
	end
end

--------------------------------------------------
-- State mutation
--------------------------------------------------
local function unlock(food: Model, ingredientName: string)
	local state = FoodState[food]
	if not state then return end
	if state.unlocked >= state.total then return end
	if state.unlockedParts[ingredientName] then return end

	local ingredientModel = food:FindFirstChild(ingredientName)
	if not ingredientModel or not ingredientModel:IsA("Model") then return end

	restore(ingredientModel, state.transparency)

	state.unlockedParts[ingredientName] = true
	state.unlocked += 1
	state.progress = state.unlocked / state.total
end

--------------------------------------------------
-- Prompt logic
--------------------------------------------------
local function handleIngredient(player: Player, food: Model, ingredientModel: Model)
	local state = FoodState[food]
	if state.unlockedParts[ingredientModel.Name] then return end
	if not ingredientModel:HasTag("Ingredients") then
		return
	end

	if ingredientModel.Name == "Soup" then
		if ingredientModel:GetAttribute("Active") ~= true then
			return
		end

		SetToolState:Invoke(ingredientModel, false)
	else
		ReleaseDraggingObject:Invoke(player)
		ingredientModel:Destroy()
	end

	unlock(food, ingredientModel.Name)
end

--------------------------------------------------
-- Food init
--------------------------------------------------
local function initFood(food: Model)
	if FoodState[food] then return end
	if not food:IsA("Model") then return end

	local total = 0
	for _, child in ipairs(food:GetChildren()) do
		if child:IsA("Model") and child.Name ~= "Bowl" then
			total += 1
		end
	end

	FoodState[food] = {
		transparency = {},
		unlockedParts = {},
		total = total,
		unlocked = 0,
		progress = 0,
	}

	for _, child in ipairs(food:GetChildren()) do
		if child:IsA("Model") and child.Name ~= "Bowl" then
			hide(child, FoodState[food].transparency)
		end
	end

	local bowl = food:FindFirstChild("Bowl")
	if not bowl then return end
	if bowl:IsA("Model") then
		bowl = bowl.PrimaryPart
	end
	if not bowl or not bowl:IsA("BasePart") then return end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = food.Name
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(5, 0)
	prompt.Parent = bowl

	prompt.Triggered:Connect(function(player)
		local draggedPart = GetDraggingObject:Invoke(player)
		if not draggedPart then return end

		local ingredientModel = draggedPart:FindFirstAncestorOfClass("Model")
		if not ingredientModel then return end

		handleIngredient(player, food, ingredientModel)

		if FoodState[food].progress >= 1 then
			prompt:Destroy()
		end
	end)
end

--------------------------------------------------
-- Bootstrap
--------------------------------------------------
for _, food in ipairs(CollectionService:GetTagged("Foods")) do
	initFood(food)
end

CollectionService:GetInstanceAddedSignal("Foods"):Connect(initFood)

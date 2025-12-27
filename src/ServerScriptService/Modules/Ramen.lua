local ServerScriptService = game:GetService("ServerScriptService")

local GetDraggingObject = ServerScriptService:WaitForChild("GetDraggingObject")
local ReleaseDraggingObject = ServerScriptService:WaitForChild("ReleaseDraggingObject")

local Ramen = {}
Ramen.__index = Ramen

local function forEachPart(model: Model, fn: (BasePart) -> ())
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			fn(inst)
		end
	end
end

function Ramen.new(model: Model)
	local ingredients = model:FindFirstChild("Ingredients")
	local required = model:GetAttribute("RequiredIngredients")
	local self = setmetatable({
		model = model,
		ingredients = ingredients,

		recipe = {},
		unlocked = {},
		transparency = {},

		total = 0,
		required = typeof(required) == "number" and required or 0,
		unlockedCount = 0,

		prompt = Instance.new("ProximityPrompt"),
		connections = {},
	}, Ramen)

	self:_initIngredients()

	if self.required <= 0 or self.required > self.total then
		self.required = self.total
	end

	self:_initPrompt()

	return self
end

function Ramen:_initIngredients()
	for _, ingredient in ipairs(self.ingredients:GetChildren()) do
		if ingredient:IsA("Model") then
			self.recipe[ingredient.Name] = true
			self.total += 1

			forEachPart(ingredient, function(part)
				self.transparency[part] = part.Transparency
				part.Transparency = 1
				part.CanCollide = false
			end)
		end
	end
end

function Ramen:_initPrompt()
	local bowl = self.model:FindFirstChild("Bowl")
	if bowl and bowl:IsA("Model") then
		bowl = bowl.PrimaryPart
	end

	local prompt = self.prompt
	prompt.ObjectText = self.model.Name
	prompt.ActionText = "Add Ingredient"
	prompt.MaxActivationDistance = 4
	prompt.RequiresLineOfSight = false
	prompt.Parent = bowl

	local function updatePromptEnabled()
		local currentPrompt = self.prompt
		if not currentPrompt then
			return
		end

		local isBeingDragged = self.model:GetAttribute("BeingDragged")
		currentPrompt.Enabled = isBeingDragged ~= true
	end

	updatePromptEnabled()
	local beingDraggedChanged = self.model:GetAttributeChangedSignal("BeingDragged"):Connect(updatePromptEnabled)
	self.connections["BeingDraggedChanged"] = beingDraggedChanged

	local Triggered
	Triggered = prompt.Triggered:Connect(function(player)
		local dragged = GetDraggingObject:Invoke(player)
		if not dragged then
			return
		end

		local ingredient = dragged:FindFirstAncestorOfClass("Model")
		if not ingredient or not self.recipe[ingredient.Name] then
			return
		end

		if ingredient.Name == "Soup" then
			if ingredient:GetAttribute("Active") ~= true then
				return
			end

			ingredient:SetAttribute("Active", false)
		else
			ReleaseDraggingObject:Invoke(player)
			ingredient:Destroy()
		end

		self:_unlock(ingredient.Name)
	end)
	self.connections["PromptTriggered"] = Triggered
end

function Ramen:_unlock(name: string)
	if self.unlocked[name] then
		return
	end

	local ingredient = self.ingredients:FindFirstChild(name)
	if not ingredient then
		return
	end

	forEachPart(ingredient, function(part)
		part.Transparency = self.transparency[part]
		part.CanCollide = true
	end)

	self.unlocked[name] = true
	self.unlockedCount += 1

	if self.unlockedCount >= self.required then
		self:Complete()
	end
end

function Ramen:Complete()
	if self.prompt then
		self.prompt:Destroy()
		self.prompt = nil
	end

	self.model:SetAttribute("Completed", true)
end

function Ramen:Destroy()
	if self.connections then
		for _, conn in pairs(self.connections) do
			conn:Disconnect()
		end
	end

	if self.prompt then
		self.prompt:Destroy()
		self.prompt = nil
	end

	self.model = nil
end

return Ramen

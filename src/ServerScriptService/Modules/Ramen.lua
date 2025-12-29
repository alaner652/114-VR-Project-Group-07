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

	self:_initTouch()

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

function Ramen:_initTouch()
	local bowlModel = self.model
	if not bowlModel or not bowlModel:IsA("Model") then
		warn("Bowl model not found")
		return
	end

	local bowlPart = bowlModel.PrimaryPart
	if not bowlPart then
		warn("Bowl has no PrimaryPart")
		return
	end

	local debounce = false

	local connection
	connection = bowlPart.Touched:Connect(function(hit)
		if debounce then
			return
		end

		local ingredient = hit:FindFirstAncestorOfClass("Model")
		if not ingredient then
			return
		end

		if not self.recipe[ingredient.Name] then
			return
		end

		if ingredient:GetAttribute("BeingDragged") ~= true then
			return
		end

		debounce = true

		if ingredient.Name == "Soup" then
			if ingredient:GetAttribute("Active") ~= true then
				debounce = false
				return
			end

			ingredient:SetAttribute("Active", false)
		else
			ReleaseDraggingObject:Invoke()
			ingredient:Destroy()
		end

		self:_unlock(ingredient.Name)

		task.delay(0.2, function()
			debounce = false
		end)
	end)

	self.connections["BowlTouched"] = connection
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

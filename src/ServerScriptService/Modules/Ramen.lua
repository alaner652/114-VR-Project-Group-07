local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local ReleaseDraggingObject = ServerScriptService:WaitForChild("ReleaseDraggingObject")

local DEBUG_UNLOCK_ALL = true

local Ramen = {}
Ramen.__index = Ramen

local function forEachPart(model: Model, fn: (BasePart) -> ())
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			fn(inst)
		end
	end
end

local function getBowlPart(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function unlockAllIngredients(self)
	for key, _ in pairs(self.recipe) do
		if not self.unlocked[key] then
			self:_unlock(key)
		end
	end

	self.model:SetAttribute("Completed", true)
end

function Ramen.new(model: Model)
	local ingredientsFolder = model:FindFirstChild("Ingredients")
	if not ingredientsFolder then
		warn(("Ramen %s has no Ingredients folder"):format(model.Name))
		return setmetatable({}, Ramen)
	end

	local required = model:GetAttribute("RequiredIngredients")

	local self = setmetatable({
		model = model,
		ingredientsFolder = ingredientsFolder,

		recipe = {},
		unlocked = {},
		hiddenProps = {},

		total = 0,
		required = typeof(required) == "number" and required or 0,
		unlockedCount = 0,

		touchConn = nil,
	}, Ramen)

	self:_cacheRecipe()

	if self.required <= 0 or self.required > self.total then
		self.required = self.total
	end

	if DEBUG_UNLOCK_ALL then
		unlockAllIngredients(self)
	else
		self:_bindTouch()
	end

	return self
end

function Ramen:_cacheRecipe()
	for _, ingredient in ipairs(self.ingredientsFolder:GetChildren()) do
		if ingredient:IsA("Model") then
			local key = ingredient:GetAttribute("IngredientType") or ingredient.Name
			self.recipe[key] = ingredient
			self.total += 1

			forEachPart(ingredient, function(part)
				local originalTransparency = part.Transparency
				if originalTransparency >= 0.99 then
					originalTransparency = 0
				end

				self.hiddenProps[part] = {
					Transparency = originalTransparency,
					CanCollide = part.CanCollide,
				}

				part.Transparency = 1
				part.CanCollide = false
			end)
		end
	end
end

function Ramen:_bindTouch()
	local bowlPart = getBowlPart(self.model)
	if not bowlPart then
		warn(("Ramen %s has no primary BasePart"):format(self.model.Name))
		return
	end

	local debounce = false

	self.touchConn = bowlPart.Touched:Connect(function(hit)
		if debounce then
			return
		end

		local ingredientModel = hit:FindFirstAncestorOfClass("Model")
		if not ingredientModel then
			return
		end

		local isDraggable = CollectionService:HasTag(ingredientModel, "Draggable")
			or CollectionService:HasTag(hit, "Draggable")

		if not isDraggable then
			return
		end

		if ingredientModel:GetAttribute("BeingDragged") ~= true then
			return
		end

		local key = ingredientModel:GetAttribute("IngredientType") or ingredientModel.Name
		if not self.recipe[key] then
			return
		end
		if self.unlocked[key] then
			return
		end

		debounce = true

		if ingredientModel.Name == "Soup" then
			if ingredientModel:GetAttribute("Active") ~= true then
				debounce = false
				return
			end
			ingredientModel:SetAttribute("Active", false)
		else
			local owner = ingredientModel.PrimaryPart and ingredientModel.PrimaryPart:GetNetworkOwner()

			if owner then
				ReleaseDraggingObject:Invoke(owner)
			end

			ingredientModel:Destroy()
		end

		self:_unlock(key)

		task.delay(0.15, function()
			debounce = false
		end)
	end)
end

function Ramen:_unlock(key: string)
	if self.unlocked[key] then
		return
	end

	local ingredient = self.recipe[key]
	if not ingredient then
		warn(("Ramen missing ingredient %s"):format(key))
		return
	end

	forEachPart(ingredient, function(part)
		local original = self.hiddenProps[part]
		if original then
			part.Transparency = original.Transparency
			part.CanCollide = original.CanCollide
		else
			part.Transparency = 0
			part.CanCollide = true
		end
	end)

	for _, inst in ipairs(ingredient:GetDescendants()) do
		if inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
			inst.Enabled = true
		end
	end

	self.unlocked[key] = true
	self.unlockedCount += 1

	if self.unlockedCount >= self.required then
		self.model:SetAttribute("Completed", true)
	end
end

function Ramen:Destroy()
	if self.touchConn then
		self.touchConn:Disconnect()
		self.touchConn = nil
	end
end

return Ramen

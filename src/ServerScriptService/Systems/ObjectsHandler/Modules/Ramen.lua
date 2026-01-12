local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local ReleaseDraggingObject = ServerScriptService.Bindables.ReleaseDraggingObject

local Ramen = {}
Ramen.__index = Ramen

local function getBowlPart(model)
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

function Ramen.new(model)
	local folder = model:FindFirstChild("Ingredients")
	if not folder then
		return setmetatable({}, Ramen)
	end

	local self = setmetatable({
		model = model,
		recipe = {},
		unlocked = {},
		required = model:GetAttribute("RequiredIngredients") or 0,
		count = 0,
	}, Ramen)

	-- cache recipe + hide
	for _, ing in ipairs(folder:GetChildren()) do
		if ing:IsA("Model") then
			local key = ing:GetAttribute("IngredientType") or ing.Name
			self.recipe[key] = ing
			self.count += 1

			for _, p in ipairs(ing:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Transparency = 1
					p.CanCollide = false
				end
			end
		end
	end

	if self.required <= 0 or self.required > self.count then
		self.required = self.count
	end

	self:_bindTouch()
	return self
end

function Ramen:_bindTouch()
	local bowl = getBowlPart(self.model)
	if not bowl then
		return
	end

	local busy = false

	bowl.Touched:Connect(function(hit)
		if busy then
			return
		end

		local item = hit:FindFirstAncestorOfClass("Model")
		if not item then
			return
		end
		if item:GetAttribute("BeingDragged") ~= true then
			return
		end

		local key = item:GetAttribute("IngredientType") or item.Name
		if not self.recipe[key] or self.unlocked[key] then
			return
		end

		-- CookState gate
		local state = item:GetAttribute("CookState")
		if state ~= nil and state ~= "Cooked" then
			return
		end

		busy = true

		if item.Name == "Soup" then
			if item:GetAttribute("Active") ~= true then
				busy = false
				return
			end
			item:SetAttribute("Active", false)
		else
			local owner = item.PrimaryPart and item.PrimaryPart:GetNetworkOwner()
			if owner then
				ReleaseDraggingObject:Invoke(owner)
			end
			item:Destroy()
		end

		self:_unlock(key)
		task.delay(0.15, function()
			busy = false
		end)
	end)
end

function Ramen:_unlock(key)
	local ing = self.recipe[key]
	if not ing then
		return
	end

	for _, p in ipairs(ing:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Transparency = 0
			p.CanCollide = true
		end
	end

	for _, v in ipairs(ing:GetDescendants()) do
		if v:IsA("ParticleEmitter") or v:IsA("Beam") or v:IsA("Trail") then
			v.Enabled = true
		end
	end

	self.unlocked[key] = true
	self.required -= 1

	if self.required <= 0 then
		self.model:SetAttribute("Completed", true)
	end
end

return Ramen

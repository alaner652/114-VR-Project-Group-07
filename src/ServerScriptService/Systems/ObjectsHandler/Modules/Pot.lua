local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Pot = {}
Pot.__index = Pot

-- ===== Tags =====
local FOOD_TAG = "Ingredients"
local STOVE_SLOT_TAG = "StoveSlot"

-- ===== Debug =====
local DEBUG = true

-- ===== Overlap =====
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

-- ===== Utilities =====
local function getBounds(obj)
	if obj:IsA("Model") then
		return obj:GetBoundingBox()
	elseif obj:IsA("BasePart") then
		return obj.CFrame, obj.Size
	end
end

local function getOverlaps(cf, size, exclude)
	overlapParams.FilterDescendantsInstances = exclude
	return Workspace:GetPartBoundsInBox(cf, size, overlapParams)
end

-- ===== Constructor =====
function Pot.new(model)
	local self = setmetatable({}, Pot)

	self.model = model
	self.containerType = model:GetAttribute("ContainerType") or "Pan"

	self.foodModels = {} -- 存 FoodRoot (Model)
	self.hasHeat = false

	if DEBUG then
		print("[Pot] New:", model:GetFullName(), "Type =", self.containerType)
	end

	self._conn = RunService.Heartbeat:Connect(function()
		self:_update()
	end)

	return self
end

-- ===== Update =====
function Pot:_update()
	self:_syncFoods()
	self:_updateHeat()

	for _, food in ipairs(self.foodModels) do
		food:SetAttribute("HasHeat", self.hasHeat)
		food:SetAttribute("InPot", true)
		food:SetAttribute("ContainerType", self.containerType)
	end
end

-- ===== Heat Detection (Slot-based) =====
function Pot:_updateHeat()
	local potPos = self.model:GetPivot().Position
	local hasHeat = false

	for _, slot in ipairs(CollectionService:GetTagged(STOVE_SLOT_TAG)) do
		if (slot.Position - potPos).Magnitude <= slot.Size.Magnitude * 0.5 then
			local stove = slot:FindFirstAncestorOfClass("Model")
			if stove and stove:GetAttribute("isOn") == true then
				hasHeat = true
				break
			end
		end
	end

	if hasHeat ~= self.hasHeat then
		self.hasHeat = hasHeat
		if DEBUG then
			print("[Pot]", hasHeat and "Heat ON" or "Heat OFF")
		end
	end
end

-- ===== Sync Foods (Model-based) =====
function Pot:_syncFoods()
	local cf, size = getBounds(self.model)
	if not cf then
		return
	end

	local found = {}

	for _, part in ipairs(getOverlaps(cf, size, { self.model })) do
		local foodRoot = part:FindFirstAncestorWhichIsA("Model")
		if foodRoot and CollectionService:HasTag(foodRoot, FOOD_TAG) then
			found[foodRoot] = true
			if not table.find(self.foodModels, foodRoot) then
				self:_addFood(foodRoot)
			end
		end
	end

	for i = #self.foodModels, 1, -1 do
		local food = self.foodModels[i]
		if not found[food] then
			self:_removeFood(food)
		end
	end
end

function Pot:_addFood(foodModel)
	self.foodModels[#self.foodModels + 1] = foodModel
	foodModel:SetAttribute("InPot", true)

	if DEBUG then
		print("[Pot] Food added:", foodModel:GetFullName())
	end
end

function Pot:_removeFood(foodModel)
	local i = table.find(self.foodModels, foodModel)
	if i then
		table.remove(self.foodModels, i)
		foodModel:SetAttribute("InPot", false)
		foodModel:SetAttribute("HasHeat", false)

		if DEBUG then
			print("[Pot] Food removed:", foodModel:GetFullName())
		end
	end
end

-- ===== Destroy =====
function Pot:Destroy()
	if DEBUG then
		print("[Pot] Destroy:", self.model:GetFullName())
	end
	if self._conn then
		self._conn:Disconnect()
	end
end

return Pot

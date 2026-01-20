local RollingPin = {}
RollingPin.__index = RollingPin

function RollingPin.new(model)
	local self = setmetatable({
		model = model,
	}, RollingPin)

	self:_initTouched()

	return self
end

function RollingPin:_initTouched()
	self.connection = self.model.PrimaryPart.Touched:Connect(function(part: BasePart)
		local ingredient = part:FindFirstAncestorOfClass("Model")
		if not ingredient then
			return
		end

		if self.model:GetAttribute("BeingDragged") ~= true then
			return
		end

		if ingredient.Name == "Dough" then
			if ingredient:GetAttribute("Active") == true then
				return
			end

			local Dough: BasePart = ingredient:FindFirstChild("Dough")
			local Hitbox: BasePart = ingredient:FindFirstChild("Hitbox")

			Dough.Size = Vector3.new(2, 0.25, 2)
			Hitbox.Size = Dough.Size

			ingredient:SetAttribute("Active", true)
		end
	end)
end

return RollingPin

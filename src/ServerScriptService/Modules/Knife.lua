local Knife = {}
Knife.__index = Knife

function Knife.new(model: Model)
	local self = setmetatable({
		model = model,
		connection = nil,
	}, Knife)

	self:_initTouched()

	return self
end

function Knife:_initTouched()
	self.connection = self.model.Touched:Connect(function(part: BasePart)
		local ingredient = part:FindFirstAncestorOfClass("Model")
		if not ingredient then
			return
		end

		if ingredient.Name == "UnCutPork" then
			local oldCF = ingredient.PrimaryPart.CFrame

			local newPork = game.ServerStorage.Ingredients:FindFirstChild("Porks"):Clone()
			newPork:SetPrimaryPartCFrame(oldCF * CFrame.new(0, 1, 0))
			newPork.Parent = ingredient.Parent

			ingredient:Destroy()
		elseif ingredient.Name == "Dough" then
			local oldCF = ingredient.PrimaryPart.CFrame

			local newNoodles = game.ServerStorage.Ingredients:FindFirstChild("Noodles"):Clone()
			newNoodles:SetPrimaryPartCFrame(oldCF * CFrame.new(0, 1, 0))
			newNoodles.Parent = ingredient.Parent

			ingredient:Destroy()
		end
	end)
end

function Knife:Destroy()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	self.model = nil
end

return Knife

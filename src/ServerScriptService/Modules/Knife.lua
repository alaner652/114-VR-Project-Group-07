-- Cuts ingredients when the knife blade touches them.
local Knife = {}
Knife.__index = Knife

function Knife.new(bladePart: BasePart)
	local self = setmetatable({
		model = bladePart:FindFirstAncestorOfClass("Model"),
		blade = bladePart,
		connection = nil,
	}, Knife)

	self:_initTouched()

	return self
end

function Knife:_initTouched()
	-- Swap ingredient models when the player is dragging the knife.
	self.connection = self.blade.Touched:Connect(function(part: BasePart)
		local ingredient = part:FindFirstAncestorOfClass("Model")
		if not ingredient then
			return
		end

		if self.model:GetAttribute("BeingDragged") ~= true then
			return
		end

		print("Knife cut:", ingredient.Name)

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
		elseif ingredient.Name == "GreenOnion" then
			local oldCF = ingredient.PrimaryPart.CFrame

			for i = 1, 3 do
				local newOnion = game.ServerStorage.Ingredients:FindFirstChild("ChoppedGreenOnion"):Clone()
				newOnion:SetPrimaryPartCFrame(oldCF * CFrame.new(0, 0.5 * i, 0))
				newOnion.Parent = ingredient.Parent
			end

			ingredient:Destroy()
		elseif ingredient.Name == "Egg" then
			local oldCF = ingredient.PrimaryPart.CFrame

			for i = 1, 2 do
				local newOnion = game.ServerStorage.Ingredients:FindFirstChild("CutEgg"):Clone()
				newOnion:SetPrimaryPartCFrame(oldCF * CFrame.new(0, 0.5 * i, 0))
				newOnion.Parent = ingredient.Parent
			end

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

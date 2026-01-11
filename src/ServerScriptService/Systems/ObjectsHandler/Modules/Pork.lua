local RunService = game:GetService("RunService")

local Pork = {}
Pork.__index = Pork

function Pork.new(model: Model)
	local self = setmetatable({
		model = model,
		cookTime = 0,
		state = "Raw",
	}, Pork)

	if model:GetAttribute("CookTime") == nil then
		model:SetAttribute("CookTime", 5)
	end
	if model:GetAttribute("CookState") == nil then
		model:SetAttribute("CookState", "Raw")
	end

	self._conn = RunService.Heartbeat:Connect(function(dt)
		self:_update(dt)
	end)

	return self
end

function Pork:_update(dt)
	if not self.model:GetAttribute("InPot") then
		return
	end

	if not self.model:GetAttribute("HasHeat") then
		return
	end

	self.cookTime += dt

	local cookTime = self.model:GetAttribute("CookTime")

	local newState
	if self.cookTime >= cookTime then
		newState = "Cooked"
	else
		newState = "Raw"
	end

	if newState ~= self.state then
		self.state = newState
		self.model:SetAttribute("CookState", newState)

		for _, p in ipairs(self.model:GetDescendants()) do
			if p:IsA("BasePart") then
				if newState == "Cooked" then
					p.Color = Color3.fromRGB(180, 120, 80)
				end
			end
		end
	end
end

function Pork:Destroy()
	if self._conn then
		self._conn:Disconnect()
	end
end

return Pork

local GasStove = {}
GasStove.__index = GasStove

local function showVFX(part: BasePart, state: boolean)
	for _, vfx in ipairs(part:GetDescendants()) do
		if vfx:IsA("ParticleEmitter") then
			vfx.Enabled = state
		end
	end
end

function GasStove.new(object: BasePart)
	local self = setmetatable({}, GasStove)
	self.object = object

	self:_init()
	return self
end

function GasStove:_init()
	self.object:SetAttribute("isOn", false)

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.Parent = self.object

	self.Triggered = clickDetector.MouseClick:Connect(function()
		self:action()
	end)
end

function GasStove:action()
	self.object:SetAttribute("isOn", not self.object:GetAttribute("isOn"))
	showVFX(self.object:FindFirstChild("CookerFire"), self.object:GetAttribute("isOn"))
end

function GasStove:Destroy()
	if self.Triggered then
		self.Triggered:Disconnect()
	end
end

return GasStove

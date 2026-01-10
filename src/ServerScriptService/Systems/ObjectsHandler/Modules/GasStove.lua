local RunService = game:GetService("RunService")

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
	self.isOn = false

	self:_init()
	return self
end

function GasStove:_init()
	print(self.object)

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.Parent = self.object

	self.Triggered = clickDetector.MouseClick:Connect(function()
		self:action()
		print(self.isOn)
	end)

	self.Update = RunService.Heartbeat:Connect(function()
		if self.isOn then
			return
		else
			return
		end
	end)
end

function GasStove:action()
	self.isOn = not self.isOn
	showVFX(self.object:FindFirstChild("CookerFire"), self.isOn)
end

function GasStove:Destroy()
	if self.Triggered then
		self.Triggered:Disconnect()
	end
	if self.Update then
		self.Update:Disconnect()
	end
end

return GasStove

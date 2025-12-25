local SoupSpoon = {}
SoupSpoon.__index = SoupSpoon

function SoupSpoon.new(model: Model)
	local self = setmetatable({
		model = model,
		below = model:FindFirstChild("Below"),
		top = model:FindFirstChild("Top"),
		connection = nil,
	}, SoupSpoon)

	self:_init()

	return self
end

function SoupSpoon:_init()
	self.connection = self.model:GetAttributeChangedSignal("Active"):Connect(function()
		local active = self.model:GetAttribute("Active") == true
		self.below.Transparency = active and 0 or 1
		self.top.Transparency = active and 0.2 or 1
	end)
end

function SoupSpoon:Destroy()
	if self.connection then
		self.connection:Disconnect()
	end

	self.model = nil
end

return SoupSpoon

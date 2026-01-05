-- Proximity prompt that activates soup from a dragged ingredient.
local ServerScriptService = game:GetService("ServerScriptService")

local Bindables = ServerScriptService:WaitForChild("Bindables")
local GetDraggingObject = Bindables:WaitForChild("GetDraggingObject")

local SoupPot = {}
SoupPot.__index = SoupPot

function SoupPot.new(model: Model)
	local self = setmetatable({
		model = model,
		prompt = nil,
		connection = nil,
	}, SoupPot)

	self:_init()
	return self
end

function SoupPot:_init()
	-- Build the prompt and disable it while the pot is dragged.
	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = self.model.Name
	prompt.MaxActivationDistance = 5
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = false
	prompt.HoldDuration = 0

	prompt.Parent = self.model

	self.connection = prompt.Triggered:Connect(function(player)
		local dragged = GetDraggingObject:Invoke(player)

		if not dragged then
			return
		end

		local ingredient = dragged:FindFirstAncestorOfClass("Model")
		if not ingredient then
			return
		end

		if ingredient.Name == "Soup" then
			ingredient:SetAttribute("Active", true)
		end
	end)
end

function SoupPot:Destroy()
	if self.connection then
		self.connection:Disconnect()
	end

	if self.dragConnection then
		self.dragConnection:Disconnect()
	end

	self.prompt:Destroy()
	self.model = nil
end

return SoupPot

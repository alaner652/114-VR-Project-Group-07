-- Proximity prompt that activates soup when the player drops an ingredient.
local ServerScriptService = game:GetService("ServerScriptService")
local GetDraggingObject = ServerScriptService:WaitForChild("GetDraggingObject")

local SoupPot = {}
SoupPot.__index = SoupPot

function SoupPot.new(model: Model)
	local self = setmetatable({
		model = model,
		prompt = Instance.new("ProximityPrompt"),
		connection = nil,
	}, SoupPot)

	self:_init()
	return self
end

function SoupPot:_init()
	-- Build the prompt and disable it while the pot is dragged.
	local prompt = self.prompt
	prompt.ObjectText = self.model.Name
	prompt.ActionText = "Interact"
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = self.model.PrimaryPart

	local function updatePromptEnabled()
		if not self.prompt then
			return
		end

		local isBeingDragged = self.model:GetAttribute("BeingDragged")
		self.prompt.Enabled = isBeingDragged ~= true
	end

	updatePromptEnabled()
	self.dragConnection = self.model:GetAttributeChangedSignal("BeingDragged"):Connect(updatePromptEnabled)

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

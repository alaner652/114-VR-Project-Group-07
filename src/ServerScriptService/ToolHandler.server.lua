local CollectionService = game:GetService("CollectionService")
local SetToolState = game.ServerScriptService.SetToolState

function Init(tool: Model)
	if not tool:IsA("Model") then return end

	if tool.Name == "Soup" then
		local below: BasePart? = tool:FindFirstChild("Below")
		local top: BasePart? = tool:FindFirstChild("Top")

		if below then below.Transparency = 1 end
		if top then top.Transparency = 1 end

		tool:SetAttribute("Full", false)
	end
end

function Activate(tool: Model)
	if not tool:IsA("Model") then return end

	if tool.Name == "Soup" then
		local below: BasePart? = tool:FindFirstChild("Below")
		local top: BasePart? = tool:FindFirstChild("Top")

		if below then below.Transparency = 0 end
		if top then top.Transparency = 0.2 end

		tool:SetAttribute("Active", true)
	end
end

function Deactivate(tool: Model)
	if not tool:IsA("Model") then return end

	if tool.Name == "Soup" then
		local below: BasePart? = tool:FindFirstChild("Below")
		local top: BasePart? = tool:FindFirstChild("Top")

		if below then below.Transparency = 1 end
		if top then top.Transparency = 1 end

		tool:SetAttribute("Active", false)
	end
end

for _, tool in ipairs(CollectionService:GetTagged("Tool")) do
	Init(tool)
end

CollectionService:GetInstanceAddedSignal("Tool"):Connect(function(tool)
	Init(tool)
end)

SetToolState.OnInvoke = function(tool, active)
	if active then
		Activate(tool)
	else
		Deactivate(tool)
	end
end
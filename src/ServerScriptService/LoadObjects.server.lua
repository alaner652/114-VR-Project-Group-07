-- Auto-initialize tagged models by mapping tags to modules.
local CollectionService = game:GetService("CollectionService")

local modulesRoot = script.Parent.Modules

local registry = {}

local function collectModules(root)
	-- Scan module folders and build the tag registry.
	for _, inst in ipairs(root:GetChildren()) do
		if inst:IsA("ModuleScript") then
			local tag = inst.Name

			registry[tag] = {
				module = require(inst),
				instances = {},
			}
		elseif inst:IsA("Folder") then
			collectModules(inst)
		end
	end
end

collectModules(modulesRoot)

local function init(tag: string, model: Model)
	local entry = registry[tag]
	if not entry or entry.instances[model] then
		return
	end

	entry.instances[model] = entry.module.new(model)
end

local function cleanup(tag: string, model: Model)
	local entry = registry[tag]
	if not entry then
		return
	end

	local obj = entry.instances[model]
	if obj then
		obj:Destroy()
		entry.instances[model] = nil
	end
end

for tag in pairs(registry) do
	for _, model in ipairs(CollectionService:GetTagged(tag)) do
		init(tag, model)
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(function(model)
		print("Added", tag, model)
		init(tag, model)
	end)

	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(model)
		cleanup(tag, model)
	end)
end

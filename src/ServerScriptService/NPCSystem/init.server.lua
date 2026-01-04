local Utils = script.Parent.Utils
local EventBus = require(Utils.EventBus)
local NPC = require(script.NPC)

local on = EventBus.on
local emit = EventBus.emit

local TablesFolder = workspace:WaitForChild("NPCSystem")

local function findAvailableSeat()
	local candidates = {}

	for _, tableModel in ipairs(TablesFolder:GetChildren()) do
		local seatsFolder = tableModel:FindFirstChild("Seats")
		local hitbox = tableModel:FindFirstChild("Hitbox")

		if seatsFolder and hitbox then
			for _, seat in ipairs(seatsFolder:GetChildren()) do
				if seat:IsA("BasePart") and not seat:GetAttribute("Active") then
					table.insert(candidates, {
						seat = seat,
						hitbox = hitbox,
						table = tableModel,
					})
				end
			end
		end
	end

	if #candidates == 0 then
		return nil
	end

	local choice = candidates[math.random(#candidates)]
	choice.seat:SetAttribute("Active", true)
	return choice
end

local State = "Idle"

function setState(newState)
	if State == newState then
		return
	end
	State = newState
	print("[INFO]", newState, "->", newState)
end

on("BatchTimeReached", function()
	if State ~= "Idle" then
		return
	end
	setState("Serving")
end)

task.spawn(function()
	while task.wait(1) do
		if State ~= "Serving" then
			continue
		end

		local result = findAvailableSeat()
		if not result then
			continue
		end

		NPC.new({ seat = result.seat, hitbox = result.hitbox })

		task.wait(math.random(1, 3))
	end
end)

local MIN_INTERVAL = 1
local MAX_INTERVAL = 1

local lastBatchTime = os.clock()
local nextInterval = math.random(MIN_INTERVAL, MAX_INTERVAL)

task.spawn(function()
	while task.wait(1) do
		if State ~= "Idle" then
			continue
		end

		local now = os.clock()
		if now - lastBatchTime >= nextInterval then
			lastBatchTime = now
			nextInterval = math.random(MIN_INTERVAL, MAX_INTERVAL)
			emit("BatchTimeReached")
		end
	end
end)

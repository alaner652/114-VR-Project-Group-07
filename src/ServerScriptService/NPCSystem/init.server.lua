local Utils = script.Parent.Utils
local EventBus = require(Utils.EventBus)
local NPC = require(script.NPC)

local on = EventBus.on
local emit = EventBus.emit

local TablesFolder = workspace:WaitForChild("NPCSystem")

local function findAvailableSeat()
	for _, tableModel in ipairs(TablesFolder:GetChildren()) do
		local seatsFolder = tableModel:FindFirstChild("Seats")
		local hitbox = tableModel:FindFirstChild("Hitbox")

		if seatsFolder and hitbox then
			for _, seat in ipairs(seatsFolder:GetChildren()) do
				if seat:IsA("BasePart") and not seat:GetAttribute("Active") then
					seat:SetAttribute("Active", true)
					return {
						seat = seat,
						hitbox = hitbox,
						table = tableModel,
					}
				end
			end
		end
	end
	return nil
end

local State = "Idle"

function setState(newState)
	if State == newState then
		return
	end
	State = newState
end

on("BatchTimeReached", function()
	if State ~= "Idle" then
		return
	end
	setState("Serving")
end)

local leavingNPCCount = 0

on("NPCStartedLeaving", function()
	leavingNPCCount += 1

	if State == "Serving" then
		setState("Leaving")
	end
end)

on("NPCFinishedLeaving", function()
	leavingNPCCount -= 1
	if leavingNPCCount < 0 then
		leavingNPCCount = 0
	end

	if leavingNPCCount == 0 then
		setState("Serving")
	end
end)

task.spawn(function()
	while true do
		task.wait(1)

		if State ~= "Serving" then
			continue
		end

		local result = findAvailableSeat()
		if not result then
			continue
		end

		NPC.new({
			seat = result.seat,
			hitbox = result.hitbox,
			table = result.table,
			events = EventBus,
		})

		task.wait(math.random(1, 3))
	end
end)

local MIN_INTERVAL = 1
local MAX_INTERVAL = 1

local lastBatchTime = os.clock()
local nextInterval = math.random(MIN_INTERVAL, MAX_INTERVAL)

task.spawn(function()
	while true do
		print("[FSM]", State, "->", State)

		task.wait(1)

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

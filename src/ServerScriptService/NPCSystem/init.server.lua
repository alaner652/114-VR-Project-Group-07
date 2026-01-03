local Utils = script.Parent.Utils
local EventBus = require(Utils.EventBus)
local NPC = require(script.NPC)

local on = EventBus.on
local emit = EventBus.emit

--------------------------------------------------
-- Leaving 狀態同步（只管「是否有人在離開」）
--------------------------------------------------
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

--------------------------------------------------
-- Seat Allocation
--------------------------------------------------
local TablesFolder = workspace:WaitForChild("Tables")

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

--------------------------------------------------
-- FSM Core
--------------------------------------------------
State = "Idle"

function setState(newState)
	if State == newState then
		return
	end
	State = newState
end

--------------------------------------------------
-- 開店（只負責啟動 Serving）
--------------------------------------------------
on("BatchTimeReached", function()
	if State ~= "Idle" then
		return
	end
	setState("Serving")
end)

--------------------------------------------------
-- Serving：持續補位（只要沒人在離開）
--------------------------------------------------
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

		print("[Serving] Filled seat:", result.seat)
		task.wait(math.random(1, 3))
	end
end)

--------------------------------------------------
-- Idle 啟動計時器（開店用）
--------------------------------------------------
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

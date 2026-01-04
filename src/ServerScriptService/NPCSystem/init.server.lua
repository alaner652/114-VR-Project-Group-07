local Utils = script.Parent.Utils
local EventBus = require(Utils.EventBus)

local NPC = require(script.Modules.NPC)

local on = EventBus.on
local emit = EventBus.emit

local TablesFolder = workspace:WaitForChild("NPCSystem")

-- =====================
-- Seat Utils
-- =====================

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

-- =====================
-- FSM
-- =====================

local State = {
	IDLE = "Idle",
	SERVING = "Serving",
}

local currentState = State.IDLE

local function setState(newState)
	if currentState == newState then
		return
	end
	print("[NPCSystem]", currentState, "->", newState)
	currentState = newState
end

-- =====================
-- Event: Batch Start
-- =====================

on("BatchTimeReached", function()
	if currentState ~= State.IDLE then
		return
	end
	setState(State.SERVING)
end)

-- =====================
-- Spawn Loop
-- =====================

task.spawn(function()
	while task.wait(1) do
		if currentState ~= State.SERVING then
			continue
		end

		local result = findAvailableSeat()
		if not result then
			-- 沒座位，自然結束這一批
			setState(State.IDLE)
			continue
		end

		local npc = NPC.new({
			seat = result.seat,
			hitbox = result.hitbox,
		})

		-- 防呆：如果 NPC 沒成功生成，釋放座位
		if not npc or npc.state == "DEAD" then
			result.seat:SetAttribute("Active", false)
		end

		task.wait(math.random(1, 3))
	end
end)

-- =====================
-- Batch Timer
-- =====================

local MIN_INTERVAL = 1
local MAX_INTERVAL = 1

local lastBatchTime = os.clock()
local nextInterval = math.random(MIN_INTERVAL, MAX_INTERVAL)

task.spawn(function()
	while task.wait(1) do
		if currentState ~= State.IDLE then
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

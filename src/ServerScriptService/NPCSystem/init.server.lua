local Players = game:GetService("Players")

local NPC = require(script.Modules.NPC)

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
-- Spawn Loop
-- =====================

local PLAYER_SCALE_MAX = 4
local INTERVAL_MIN_AT_ONE = 10
local INTERVAL_MAX_AT_ONE = 13
local INTERVAL_MIN_AT_MAX = 3
local INTERVAL_MAX_AT_MAX = 6
local SPAWN_IDLE_CHECK = 0.5
local SPAWN_JITTER = 1

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function randRange(min, max)
	return min + (max - min) * math.random()
end

local function getSpawnInterval()
	local playerCount = #Players:GetPlayers()
	local t = math.clamp(playerCount / PLAYER_SCALE_MAX, 0, 1)

	local minInterval = lerp(INTERVAL_MIN_AT_ONE, INTERVAL_MIN_AT_MAX, t)
	local maxInterval = lerp(INTERVAL_MAX_AT_ONE, INTERVAL_MAX_AT_MAX, t)

	local interval = randRange(minInterval, maxInterval)
	local jitter = randRange(-SPAWN_JITTER, SPAWN_JITTER)

	return math.max(1, interval + jitter)
end

task.spawn(function()
	while true do
		local result = findAvailableSeat()
		if not result then
			task.wait(SPAWN_IDLE_CHECK)
			continue
		end

		local npc = NPC.new({
			seat = result.seat,
			hitbox = result.hitbox,
		})

		-- Safety: if NPC failed to spawn, release the seat
		if not npc or npc.state == "DEAD" then
			result.seat:SetAttribute("Active", false)
		end

		task.wait(getSpawnInterval())
	end
end)

-- NPC spawner with a seat pool and player-scaled timing.
local Players = game:GetService("Players")

print("[NPCSystem] Init starting")

local TablesFolder = workspace:WaitForChild("NPCSystem"):WaitForChild("Tables")

local NPC = require(script.Modules.NPC)

-- =====================
-- Seat Pool
-- =====================

-- Seat pool for fast random selection and release.
local availableSeats = {}
local seatIndexBySeat = {}
local seatMetaBySeat = {}
local seatConnections = {}
local tableConnections = {}
local DEBUG_POOL_LOG = true
local DEBUG_TABLE_LOG = true
local lastPoolLog = 0
local lastNoSeatLog = 0
local warnedTables = {}

local function logPool(reason)
	if not DEBUG_POOL_LOG then
		return
	end
	local now = os.clock()
	if now - lastPoolLog < 0.5 then
		return
	end
	lastPoolLog = now
	print(("[NPCSystem] SeatPool %s | available=%d"):format(reason, #availableSeats))
end

local function addSeatToPool(seat)
	if seatIndexBySeat[seat] then
		return
	end
	if not seatMetaBySeat[seat] then
		return
	end
	if seat:GetAttribute("Active") == true then
		return
	end

	availableSeats[#availableSeats + 1] = seat
	seatIndexBySeat[seat] = #availableSeats
	logPool("add")
end

local function removeSeatFromPool(seat)
	local index = seatIndexBySeat[seat]
	if not index then
		return
	end

	local lastIndex = #availableSeats
	local lastSeat = availableSeats[lastIndex]

	availableSeats[index] = lastSeat
	availableSeats[lastIndex] = nil
	seatIndexBySeat[seat] = nil

	if lastSeat and lastSeat ~= seat then
		seatIndexBySeat[lastSeat] = index
	end
	logPool("remove")
end

local function cleanupSeat(seat)
	removeSeatFromPool(seat)
	seatMetaBySeat[seat] = nil

	local conns = seatConnections[seat]
	if conns then
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
		seatConnections[seat] = nil
	end
end

local function registerSeat(seat, hitbox, tableModel)
	if seatMetaBySeat[seat] then
		return
	end

	seatMetaBySeat[seat] = {
		seat = seat,
		hitbox = hitbox,
		table = tableModel,
	}

	if seat:GetAttribute("Active") ~= true then
		addSeatToPool(seat)
	end

	local conns = {}

	conns[#conns + 1] = seat:GetAttributeChangedSignal("Active"):Connect(function()
		if seat:GetAttribute("Active") == true then
			removeSeatFromPool(seat)
		else
			addSeatToPool(seat)
		end
	end)

	conns[#conns + 1] = seat.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cleanupSeat(seat)
		end
	end)

	seatConnections[seat] = conns
end

local function registerTable(tableModel)
	if tableConnections[tableModel] then
		return
	end

	local seatsFolder = tableModel:FindFirstChild("Seats")
	local hitbox = tableModel:FindFirstChild("Hitbox")
	if not seatsFolder or not hitbox then
		if not warnedTables[tableModel] then
			warnedTables[tableModel] = true
			warn(("[NPCSystem] Table %s missing Seats or Hitbox"):format(tableModel.Name))
		end
		return
	end

	local seatCount = 0
	local activeCount = 0
	for _, seat in ipairs(seatsFolder:GetChildren()) do
		if seat:IsA("BasePart") then
			seatCount += 1
			if seat:GetAttribute("Active") == true then
				activeCount += 1
			end
			registerSeat(seat, hitbox, tableModel)
		end
	end
	if DEBUG_TABLE_LOG then
		print(("[NPCSystem] Table %s seats=%d active=%d"):format(tableModel.Name, seatCount, activeCount))
	end

	local conns = {}

	conns[#conns + 1] = seatsFolder.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") then
			registerSeat(child, hitbox, tableModel)
		end
	end)

	conns[#conns + 1] = seatsFolder.ChildRemoved:Connect(function(child)
		if child:IsA("BasePart") then
			cleanupSeat(child)
		end
	end)

	conns[#conns + 1] = tableModel.AncestryChanged:Connect(function(_, parent)
		if not parent then
			for _, seat in ipairs(seatsFolder:GetChildren()) do
				if seat:IsA("BasePart") then
					cleanupSeat(seat)
				end
			end
			for _, conn in ipairs(conns) do
				conn:Disconnect()
			end
			tableConnections[tableModel] = nil
		end
	end)

	tableConnections[tableModel] = conns
end

local function findAvailableSeat()
	while #availableSeats > 0 do
		local index = math.random(#availableSeats)
		local seat = availableSeats[index]
		removeSeatFromPool(seat)

		local meta = seatMetaBySeat[seat]
		if seat and seat.Parent and meta and meta.hitbox and meta.hitbox.Parent then
			seat:SetAttribute("Active", true)
			return meta
		end

		cleanupSeat(seat)
	end

	return nil
end

for _, tableModel in ipairs(TablesFolder:GetChildren()) do
	if tableModel:IsA("Model") then
		registerTable(tableModel)
	end
end

print(("[NPCSystem] Tables ready | available seats=%d"):format(#availableSeats))

TablesFolder.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		registerTable(child)
	end
end)

-- =====================
-- Spawn Timing
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
	print("[NPCSystem] Spawn loop started")
	while true do
		local result = findAvailableSeat()
		if not result then
			local now = os.clock()
			if now - lastNoSeatLog > 5 then
				lastNoSeatLog = now
				print("[NPCSystem] No available seats")
			end
			task.wait(SPAWN_IDLE_CHECK)
			continue
		end

		local npc = NPC.new({
			seat = result.seat,
			hitbox = result.hitbox,
		})

		-- Release the seat if the NPC failed to spawn.
		if not npc or npc.state == "DEAD" then
			result.seat:SetAttribute("Active", false)
		end

		task.wait(getSpawnInterval())
	end
end)

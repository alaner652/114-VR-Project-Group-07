-- NPC.lua (ModuleScript)
-- Robust NPC pathing with LRU cache + return via reversed entry path (skip C)

-- ============================================
-- Services
-- ============================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

-- ============================================
-- Config
-- ============================================
local NPCFolder = ReplicatedStorage:WaitForChild("NPCs")
local NPCSpawn = workspace:WaitForChild("NPCSystem"):WaitForChild("NPCSpawn")
local NPCContainer = workspace:WaitForChild("NPCs")

local LEAVE_TIME = 120

local AGENT_RADIUS = 3
local AGENT_HEIGHT = 5
local AGENT_CAN_JUMP = false

-- cache key quantization: bigger -> fewer keys -> better cache hit
local GRID = 2 -- studs

-- movement tuning
local REPLAN_LIMIT = 3 -- how many replans when stuck
local WAYPOINT_SKIP_DIST = 1.0 -- skip waypoint if already close
local MOVE_TIMEOUT = 6 -- seconds max waiting for a single MoveToFinished
local YIELD_ON_SPAWN = true -- give physics one heartbeat after spawn
local LEAVE_OFFSET = CFrame.new(0, 0, -2) -- teleport offset at leaving (from hitbox)
local SEAT_REACH_TIMEOUT = 20 -- seconds before abandoning unseated NPC

-- ============================================
-- LRU Path Cache (no lastUsed, no nil crash)
-- key -> path (array of Vector3)
-- order: least-recent at [1], most-recent at [#]
-- ============================================
local PATH_CACHE = {
	maxSize = 30,
	store = {}, -- key -> path
	order = {}, -- array of keys (unique)
}

local function q(n)
	return math.floor(n / GRID) * GRID
end

local function makeKey(fromPos, toPos)
	return string.format(
		"%d_%d_%d|%d_%d_%d",
		q(fromPos.X),
		q(fromPos.Y),
		q(fromPos.Z),
		q(toPos.X),
		q(toPos.Y),
		q(toPos.Z)
	)
end

local function touchKey(key)
	-- ensure unique + move to the end (most recent)
	for i = #PATH_CACHE.order, 1, -1 do
		if PATH_CACHE.order[i] == key then
			table.remove(PATH_CACHE.order, i)
			break
		end
	end
	table.insert(PATH_CACHE.order, key)
end

local function cacheGet(fromPos, toPos)
	local key = makeKey(fromPos, toPos)
	local path = PATH_CACHE.store[key]
	if path then
		touchKey(key)
		return path
	end
	return nil
end

local function cacheSet(fromPos, toPos, path)
	if not path then
		return
	end

	local key = makeKey(fromPos, toPos)

	-- if already exists, just overwrite + touch
	PATH_CACHE.store[key] = path
	touchKey(key)

	-- evict LRU
	while #PATH_CACHE.order > PATH_CACHE.maxSize do
		local oldestKey = table.remove(PATH_CACHE.order, 1)
		PATH_CACHE.store[oldestKey] = nil
	end
end

-- ============================================
-- Utils
-- ============================================
local function safeEmit(events, name, payload)
	if not events then
		return
	end
	local ok, err = pcall(function()
		events.emit(name, payload)
	end)
	if not ok then
		warn("[NPC] Event emit failed:", name, err)
	end
end

local function spawnModel()
	local rig = NPCFolder:FindFirstChild("Rig")
	if not rig then
		warn("[NPC] Rig not found in ReplicatedStorage.NPCs")
		return nil
	end

	local model = rig:Clone()
	model.Parent = NPCContainer

	-- ensure PrimaryPart exists
	if not model.PrimaryPart then
		-- try common names
		local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
		if root then
			model.PrimaryPart = root
		end
	end

	return model
end

local function computePath(fromPos, toPos)
	-- always protected: never hard-crash caller
	local ok, result = pcall(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = AGENT_RADIUS,
			AgentHeight = AGENT_HEIGHT,
			AgentCanJump = AGENT_CAN_JUMP,
		})
		path:ComputeAsync(fromPos, toPos)

		if path.Status ~= Enum.PathStatus.Success then
			return nil
		end

		local pts = {}
		for _, wp in ipairs(path:GetWaypoints()) do
			table.insert(pts, wp.Position)
		end
		return pts
	end)

	if not ok then
		warn("[NPC] computePath error:", result)
		return nil
	end

	return result
end

-- compute with cache (multi-destination supported)
local function getOrComputePath(fromPos, toPos)
	local cached = cacheGet(fromPos, toPos)
	if cached then
		return cached
	end

	local fresh = computePath(fromPos, toPos)
	if fresh then
		cacheSet(fromPos, toPos, fresh)
	end
	return fresh
end

-- ============================================
-- NPC Class
-- ============================================
local NPC = {}
NPC.__index = NPC

function NPC.new(context)
	local self = setmetatable({}, NPC)

	self.seat = context.seat
	self.hitbox = context.hitbox
	self.events = context.events

	self.destroyed = false
	self.isLeaving = false
	self.seated = false
	self.waiting = false
	self._hitboxConn = nil

	self.model = spawnModel()
	if not self.model or not self.model.PrimaryPart then
		warn("[NPC] spawnModel failed or no PrimaryPart")
		if self.seat then
			self.seat:SetAttribute("Active", false)
		end
		self.destroyed = true
		return self
	end

	-- spawn
	self.model:SetPrimaryPartCFrame(NPCSpawn.CFrame)

	if YIELD_ON_SPAWN then
		RunService.Heartbeat:Wait()
	end

	-- seat lock
	if self.seat then
		self.seat:SetAttribute("Active", true)
	end

	-- PRE-COMPUTE entry path using stable fromPos to maximize cache hit:
	-- use NPCSpawn.Position instead of current root.Position (reduces key diversity)
	self.entryPath = getOrComputePath(NPCSpawn.Position, self.hitbox.Position)

	self:_enterShop()

	return self
end

-- ============================================
-- Movement
-- ============================================
function NPC:_getHumanoid()
	if not self.model then
		return nil
	end
	return self.model:FindFirstChildOfClass("Humanoid")
end

function NPC:_moveTo(pos)
	if self.destroyed then
		return false
	end

	local humanoid = self:_getHumanoid()
	if not humanoid then
		return false
	end

	humanoid:MoveTo(pos)

	-- MoveToFinished can hang; enforce a timeout
	local done = false
	local reached = false

	local conn
	conn = humanoid.MoveToFinished:Connect(function(ok)
		reached = ok
		done = true
		if conn then
			conn:Disconnect()
		end
	end)

	local t0 = os.clock()
	while not done do
		if self.destroyed then
			if conn then
				conn:Disconnect()
			end
			return false
		end
		if os.clock() - t0 > MOVE_TIMEOUT then
			if conn then
				conn:Disconnect()
			end
			return false
		end
		RunService.Heartbeat:Wait()
	end

	return reached
end

function NPC:_walkPathWithReplan(path, finalTarget, depth)
	depth = depth or 0
	if depth > REPLAN_LIMIT then
		return false
	end
	if not path or #path == 0 then
		return false
	end

	for _, pos in ipairs(path) do
		if self.destroyed then
			return false
		end

		-- already close -> skip
		local root = self.model and self.model.PrimaryPart
		if root and (root.Position - pos).Magnitude < WAYPOINT_SKIP_DIST then
			continue
		end

		local ok = self:_moveTo(pos)
		if not ok then
			-- replan from current position to finalTarget (and cached)
			local root2 = self.model and self.model.PrimaryPart
			if not root2 then
				return false
			end

			local replanned = getOrComputePath(root2.Position, finalTarget)
			if replanned then
				return self:_walkPathWithReplan(replanned, finalTarget, depth + 1)
			end
			return false
		end
	end

	return true
end

-- ============================================
-- Enter / Seat
-- ============================================
function NPC:_enterShop()
	if self.destroyed then
		return
	end

	-- walk to hitbox (async)
	task.spawn(function()
		if self.destroyed then
			return
		end

		if self.entryPath then
			self:_walkPathWithReplan(self.entryPath, self.hitbox.Position)
		else
			-- no path -> try compute once now
			local root = self.model and self.model.PrimaryPart
			if root then
				local p = getOrComputePath(root.Position, self.hitbox.Position)
				if p then
					self.entryPath = p
					self:_walkPathWithReplan(p, self.hitbox.Position)
				end
			end
		end
	end)

	-- timeout in case NPC never reaches seat (prevents seat lock buildup)
	task.spawn(function()
		local t0 = os.clock()
		while not self.destroyed and not self.seated do
			if os.clock() - t0 >= SEAT_REACH_TIMEOUT then
				self:Destroy(false)
				return
			end
			task.wait(1)
		end
	end)

	-- seat detection via hitbox touch
	self._hitboxConn = self.hitbox.Touched:Connect(function(part)
		if self.destroyed then
			if self._hitboxConn then
				self._hitboxConn:Disconnect()
				self._hitboxConn = nil
			end
			return
		end
		if not part:IsDescendantOf(self.model) then
			return
		end
		if self.seated then
			return
		end

		self.seated = true

		-- weld to seat
		local weld = Instance.new("Motor6D")
		weld.Name = "SeatWeld"
		weld.Part0 = self.seat
		weld.Part1 = self.model.PrimaryPart
		weld.C0 = CFrame.new(0, 3, 0)
		weld.Parent = self.model.PrimaryPart

		local humanoid = self:_getHumanoid()
		if humanoid then
			humanoid.Sit = true
		end

		self:_startWaitingTimer()

		if self._hitboxConn then
			self._hitboxConn:Disconnect()
			self._hitboxConn = nil
		end
	end)
end

function NPC:_startWaitingTimer()
	if self.waiting or self.destroyed then
		return
	end
	self.waiting = true

	task.spawn(function()
		local remaining = LEAVE_TIME
		while remaining > 0 do
			if self.destroyed or self.isLeaving then
				return
			end
			if self.model then
				self.model.Name = tostring(remaining)
			end
			task.wait(1)
			remaining -= 1
		end

		if self.model then
			self.model.Name = "0"
		end

		self:startLeaving()
	end)
end

-- ============================================
-- Leaving: reverse entry path but IGNORE C (last waypoint)
-- ============================================
function NPC:startLeaving()
	if self.isLeaving or self.destroyed then
		return
	end
	self.isLeaving = true

	safeEmit(self.events, "NPCStartedLeaving")

	-- stand up + unweld
	local humanoid = self:_getHumanoid()
	if humanoid then
		humanoid.Sit = false
	end

	local weld = self.model and self.model.PrimaryPart and self.model.PrimaryPart:FindFirstChild("SeatWeld")
	if weld then
		weld:Destroy()
	end

	-- small reposition to avoid floor snag at seat area
	if self.model and self.model.PrimaryPart then
		self.model:SetPrimaryPartCFrame(self.hitbox.CFrame * LEAVE_OFFSET)
		RunService.Heartbeat:Wait()
	end

	-- Build reverse path excluding C:
	-- entryPath = [A, B, C] (C near hitbox)
	-- reverse should be [B, A]
	local reverse = nil
	if self.entryPath and #self.entryPath >= 2 then
		reverse = {}
		for i = #self.entryPath - 1, 1, -1 do
			table.insert(reverse, self.entryPath[i])
		end
	end

	local ok = false
	if reverse and #reverse > 0 then
		ok = self:_walkPathWithReplan(reverse, NPCSpawn.Position)
	end

	if not ok then
		-- fallback: compute from current to spawn (cached too)
		local root = self.model and self.model.PrimaryPart
		if root then
			local fb = getOrComputePath(root.Position, NPCSpawn.Position)
			if fb then
				self:_walkPathWithReplan(fb, NPCSpawn.Position)
			end
		end
	end

	self:Destroy()
end

-- ============================================
-- Destroy
-- ============================================
function NPC:Destroy(emitLeavingFinished)
	if self.destroyed then
		return
	end
	self.destroyed = true

	if self._hitboxConn then
		self._hitboxConn:Disconnect()
		self._hitboxConn = nil
	end

	-- free seat
	if self.seat then
		self.seat:SetAttribute("Active", false)
	end

	-- destroy model
	if self.model then
		self.model:Destroy()
		self.model = nil
	end

	if emitLeavingFinished == nil then
		emitLeavingFinished = self.isLeaving
	end
	if emitLeavingFinished then
		safeEmit(self.events, "NPCFinishedLeaving")
	end
end

return NPC

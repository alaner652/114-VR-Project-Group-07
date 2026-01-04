local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Utils = require(script.Parent.Utils)

local NPCSpawn = workspace:WaitForChild("NPCSystem"):WaitForChild("NPCSpawn")

-- =====================
-- 基本設定
-- =====================

local WAIT_FOOD_TIME = 120 -- 等待上菜的秒數
local EAT_TIME = 20 -- 吃飯時間(秒)

local SERVE_BOX_SIZE = Vector3.new(2, 2, 3)
local SERVE_BOX_OFFSET = CFrame.new(0, -0.6, -2)

local SERVE_CLAIM_ATTR = "ServingNPC"
local SERVE_CLAIM_DIST_ATTR = "ServingNPCDist2"

local PATH_PARAMS = {
	AgentRadius = 3,
	AgentHeight = 5,
	AgentCanJump = true,
}

local MAX_RETRY = 3
local MAX_MOVE_TIME = 6

local State = {
	ENTERING = "ENTERING",
	WAITING = "WAITING",
	EATING = "EATING",
	LEAVING = "LEAVING",
	DEAD = "DEAD",
}

-- =====================
-- NPC Class
-- =====================

local NPC = {}
NPC.__index = NPC

local NEXT_ID = 0

-- =====================
-- Utils
-- =====================

local function log(id, msg)
	print(("[NPC %d] %s"):format(id, msg))
end

local function logWarn(id, msg)
	warn(("[NPC %d] %s"):format(id, msg))
end

local function reverseWaypointsSkipLast(list)
	local out = {}
	local function push(i)
		if i < 1 then
			return
		end
		out[#out + 1] = list[i]
		push(i - 1)
	end
	push(#list - 1)
	return out
end

local function dist2(a, b)
	local d = a - b
	return d.X * d.X + d.Y * d.Y + d.Z * d.Z
end

local function clearServeClaim(model, npcId)
	if model and model.Parent and model:GetAttribute(SERVE_CLAIM_ATTR) == npcId then
		model:SetAttribute(SERVE_CLAIM_ATTR, nil)
		model:SetAttribute(SERVE_CLAIM_DIST_ATTR, nil)
	end
end

-- =====================
-- Constructor
-- =====================

function NPC.new(context)
	NEXT_ID += 1

	local model = Utils:spawnModel()
	if not model then
		logWarn(NEXT_ID, "Spawn failed")
		return nil
	end

	local self = setmetatable({
		id = NEXT_ID,

		seat = context.seat,
		hitbox = context.hitbox,

		model = model,
		humanoid = model:FindFirstChildOfClass("Humanoid"),

		enterWaypoints = nil,
		lastWaypointIndex = 1,
		retryCount = 0,

		state = State.ENTERING,
		timer = 0,

		food = nil,
		claimedFood = nil,

		seatWeld = nil, -- Motor6D
		foodWeld = nil, -- WeldConstraint

		serveParams = nil,

		_tickConn = nil,
	}, NPC)

	-- 沒 Humanoid 或主零件就直接清掉，避免後續狀態壞掉
	if not self.humanoid or not self.model.PrimaryPart then
		logWarn(self.id, "Missing Humanoid or PrimaryPart")
		self:Destroy()
		return nil
	end

	-- 先放到出生點
	self.model:SetPrimaryPartCFrame(NPCSpawn.CFrame)

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.model, self.seat }
	self.serveParams = params

	log(self.id, "Spawned")
	self:_enterShop()
	return self
end

-- =====================
-- Tick Loop
-- =====================

function NPC:_startTickLoop()
	if self._tickConn then
		return
	end

	local elapsed = 0
	self._tickConn = RunService.Heartbeat:Connect(function(dt)
		if self.state == State.DEAD then
			self:_stopTickLoop()
			return
		end

		elapsed += dt
		if elapsed < 1 then
			return
		end

		elapsed -= 1
		NPC.Tick(self)
	end)
end

function NPC:_stopTickLoop()
	if self._tickConn then
		self._tickConn:Disconnect()
		self._tickConn = nil
	end
end

-- =====================
-- State
-- =====================

function NPC:_setState(newState, time)
	if self.state == State.DEAD then
		return
	end

	self.state = newState
	self.timer = time or 0

	if newState == State.WAITING or newState == State.EATING then
		self:_startTickLoop()
	else
		self:_stopTickLoop()
	end

	log(self.id, ("State -> %s (%ds)"):format(newState, self.timer))

	if newState == State.LEAVING then
		self:_onLeaving()
	end
end

-- Tick 只負責更新狀態，節拍由 _startTickLoop 控制
function NPC:Tick()
	if self.state == State.DEAD then
		return
	end
	if not self.model then
		self:Destroy()
		return
	end

	-- 方便在 Studio 直接看到狀態
	self.model.Name = ("%s (%ds)"):format(self.state, math.max(0, self.timer))

	-- 等待時嘗試收菜
	if self.state == State.WAITING then
		self:_tryServe()
	end

	-- 計時器
	if self.timer > 0 then
		self.timer -= 1
	else
		-- 等待/吃完時間到就離開
		if self.state == State.WAITING or self.state == State.EATING then
			self:_setState(State.LEAVING)
		end
	end
end

-- =====================
-- Movement (Event-driven)
-- =====================

function NPC:_computePath(startPos, goalPos)
	local path = PathfindingService:CreatePath(PATH_PARAMS)
	path:ComputeAsync(startPos, goalPos)
	if path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	return path:GetWaypoints()
end

function NPC:_moveToAsync(pos, onFinish)
	local humanoid = self.humanoid
	if not humanoid or not humanoid.Parent then
		if onFinish then
			onFinish(false)
		end
		return
	end

	local done = false
	local conn

	local function finish(ok)
		if done then
			return
		end
		done = true
		if conn then
			conn:Disconnect()
		end
		if onFinish then
			onFinish(ok)
		end
	end

	conn = humanoid.MoveToFinished:Connect(function(ok)
		finish(ok)
	end)

	humanoid:MoveTo(pos)
	task.delay(MAX_MOVE_TIME, function()
		finish(false)
	end)
end

function NPC:_followWaypoints(waypoints, onFinish)
	local function step(index)
		if self.state == State.DEAD then
			return
		end

		local humanoid = self.humanoid
		if not humanoid or not humanoid.Parent then
			return
		end

		if index > #waypoints then
			if onFinish then
				onFinish()
			end
			return
		end

		self.lastWaypointIndex = index

		self:_moveToAsync(waypoints[index].Position, function(ok)
			if self.state == State.DEAD then
				return
			end

			if not ok then
				self.retryCount += 1
				logWarn(self.id, ("Move interrupted (%d/%d) at waypoint %d"):format(self.retryCount, MAX_RETRY, index))

				if self.retryCount >= MAX_RETRY then
					logWarn(self.id, "Too many retries -> Destroy")
					self:Destroy()
					return
				end

				self.lastWaypointIndex = math.max(1, index - 1)
				task.delay(0.5, function()
					step(self.lastWaypointIndex)
				end)
				return
			end

			step(index + 1)
		end)
	end

	step(self.lastWaypointIndex)
end

-- =====================
-- Enter / Sit
-- =====================

function NPC:_enterShop()
	local waypoints = self:_computePath(NPCSpawn.Position, self.hitbox.Position)
	if not waypoints then
		logWarn(self.id, "Path compute failed (enter)")
		self:Destroy()
		return
	end

	self.enterWaypoints = waypoints
	self.lastWaypointIndex = 1
	self.retryCount = 0

	log(self.id, "Entering")
	self:_followWaypoints(waypoints, function()
		self:_sit()
	end)
end

function NPC:_sit()
	if self.state == State.DEAD then
		return
	end

	local root = self.model and self.model.PrimaryPart
	if not root then
		logWarn(self.id, "Missing PrimaryPart on sit")
		self:Destroy()
		return
	end

	-- 建立座位焊接
	local weld = Instance.new("Motor6D")
	weld.Name = "SeatWeld"
	weld.Part0 = self.seat
	weld.Part1 = root

	-- 把 NPC 移到座位上方
	local offsetY = (self.seat.Size.Y * 0.5) + (root.Size.Y * 0.5)
	root.CFrame = self.seat.CFrame * CFrame.new(0, offsetY, 0)

	-- 用 C0/C1 固定坐姿
	weld.C0 = self.seat.CFrame:ToObjectSpace(root.CFrame)
	weld.C1 = CFrame.new()
	weld.Parent = root

	self.seatWeld = weld

	if self.humanoid then
		self.humanoid.Sit = true
	end

	self:_setState(State.WAITING, WAIT_FOOD_TIME)
end

-- =====================
-- Serve / Eat (Claim + WeldConstraint)
-- =====================

function NPC:_tryServe()
	if self.state ~= State.WAITING then
		return
	end

	local model = self.model
	local primary = model and model.PrimaryPart
	if not primary or not self.serveParams then
		return
	end

	local boxCFrame = primary.CFrame * SERVE_BOX_OFFSET
	local parts = workspace:GetPartBoundsInBox(boxCFrame, SERVE_BOX_SIZE, self.serveParams)

	local function tryPart(index)
		if index > #parts then
			return
		end

		local part = parts[index]
		local ramenModel = part:FindFirstAncestorOfClass("Model")
		if not ramenModel then
			return tryPart(index + 1)
		end

		if not CollectionService:HasTag(ramenModel, "Ramen") then
			return tryPart(index + 1)
		end
		if ramenModel:GetAttribute("Completed") ~= true then
			return tryPart(index + 1)
		end
		if ramenModel:GetAttribute("BeingDragged") == true then
			return tryPart(index + 1)
		end

		local ramenRoot = ramenModel.PrimaryPart
		if not ramenRoot then
			return tryPart(index + 1)
		end

		-- 已被其他 NPC 接走就跳過
		if ramenRoot:FindFirstChild("FoodWeld") then
			return tryPart(index + 1)
		end

		-- 用距離做 claim，避免同一碗被多個 NPC 搶走
		local myDist2 = dist2(primary.Position, ramenRoot.Position)
		local curNpc = ramenModel:GetAttribute(SERVE_CLAIM_ATTR)
		local curDist = ramenModel:GetAttribute(SERVE_CLAIM_DIST_ATTR)

		if curNpc ~= nil and curNpc ~= self.id and curDist ~= nil and curDist <= myDist2 then
			return tryPart(index + 1)
		end

		ramenModel:SetAttribute(SERVE_CLAIM_ATTR, self.id)
		ramenModel:SetAttribute(SERVE_CLAIM_DIST_ATTR, myDist2)

		-- 下一幀再確認，讓其他 NPC 有機會搶先
		self.claimedFood = ramenModel

		task.spawn(function()
			RunService.Heartbeat:Wait()

			-- 狀態變了就放棄 claim
			if self.state ~= State.WAITING then
				clearServeClaim(ramenModel, self.id)
				if self.claimedFood == ramenModel then
					self.claimedFood = nil
				end
				return
			end

			if ramenModel:GetAttribute(SERVE_CLAIM_ATTR) ~= self.id then
				if self.claimedFood == ramenModel then
					self.claimedFood = nil
				end
				return
			end

			self:_eat(ramenModel)
		end)
	end

	tryPart(1)
end

function NPC:_eat(ramenModel)
	-- 只能從等待狀態開始吃
	if self.state ~= State.WAITING then
		clearServeClaim(ramenModel, self.id)
		return
	end
	if not self.model or not self.model.PrimaryPart then
		clearServeClaim(ramenModel, self.id)
		self:Destroy()
		return
	end

	local npcRoot = self.model.PrimaryPart
	local ramenRoot = ramenModel.PrimaryPart
	if not ramenRoot then
		clearServeClaim(ramenModel, self.id)
		return
	end

	-- 已被焊住代表被別人拿走
	if ramenRoot:FindFirstChild("FoodWeld") then
		clearServeClaim(ramenModel, self.id)
		if self.claimedFood == ramenModel then
			self.claimedFood = nil
		end
		return
	end

	-- 把拉麵焊到 NPC 身上
	local weld = Instance.new("WeldConstraint")
	weld.Name = "FoodWeld"
	weld.Part0 = npcRoot
	weld.Part1 = ramenRoot
	weld.Parent = ramenRoot

	self.food = ramenModel
	self.foodWeld = weld

	log(self.id, "Start eating")
	self:_setState(State.EATING, EAT_TIME)
end

-- =====================
-- Leaving / Cleanup
-- =====================

function NPC:_onLeaving()
	if self.state == State.DEAD then
		return
	end

	log(self.id, "Leaving")

	-- 站起來
	if self.humanoid then
		self.humanoid.Sit = false
	end

	-- 清掉餐點與 claim
	if self.food then
		clearServeClaim(self.food, self.id)
		if self.food.Parent then
			self.food:Destroy()
		end
	end
	self.food = nil

	-- 放掉可能還沒吃到的餐點 claim
	clearServeClaim(self.claimedFood, self.id)
	self.claimedFood = nil

	-- FoodWeld 會跟著拉麵一起銷毀，這裡只清參考
	self.foodWeld = nil

	-- 清掉座位焊接
	if self.seatWeld and self.seatWeld.Parent then
		self.seatWeld:Destroy()
	end
	self.seatWeld = nil

	-- 先把角色移回出口，再走回出生點
	local root = self.model and self.model.PrimaryPart
	if not root then
		self:Destroy()
		return
	end

	-- 等一幀再挪位置，避免碰撞卡住
	RunService.Heartbeat:Wait()
	root.CFrame = self.hitbox.CFrame
	RunService.Heartbeat:Wait()

	-- 沒有回程路徑就直接清掉
	if not self.enterWaypoints then
		self:Destroy()
		return
	end

	local back = reverseWaypointsSkipLast(self.enterWaypoints)
	self.lastWaypointIndex = 1
	self.retryCount = 0

	self:_followWaypoints(back, function()
		self:Destroy()
	end)
end

function NPC:Destroy()
	if self.state == State.DEAD then
		return
	end
	self.state = State.DEAD
	self:_stopTickLoop()
	log(self.id, "Destroyed")

	-- 清掉 claim，避免殘留
	clearServeClaim(self.claimedFood, self.id)
	clearServeClaim(self.food, self.id)
	self.claimedFood = nil

	-- 釋放座位
	if self.seat then
		self.seat:SetAttribute("Active", false)
	end

	-- 清掉模型
	if self.model then
		self.model:Destroy()
		self.model = nil
	end

	-- 清掉參考
	self.humanoid = nil
	self.enterWaypoints = nil
	self.seatWeld = nil
	self.food = nil
	self.foodWeld = nil
	self.serveParams = nil
end

return NPC

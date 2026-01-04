local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local Utils = require(script.Parent.Utils)

local NPCSpawn = workspace:WaitForChild("NPCSystem"):WaitForChild("NPCSpawn")

-- =====================
-- Config
-- =====================

local WAIT_FOOD_TIME = 120
local EAT_TIME = 20 -- 吃飯一定刷新成 20 秒

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

local function reverseWaypointsSkipLast(list)
	local out = {}
	for i = #list - 1, 1, -1 do
		out[#out + 1] = list[i]
	end
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

		_tickTask = nil,
	}, NPC)

	-- 基本檢查
	if not self.humanoid or not self.model.PrimaryPart then
		self:Destroy()
		return nil
	end

	-- 避免一開始生成在奇怪位置
	self.model:SetPrimaryPartCFrame(NPCSpawn.CFrame)

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.model, self.seat }
	self.serveParams = params

	self:_enterShop()
	return self
end

-- =====================
-- Tick Loop
-- =====================

function NPC:_startTickLoop()
	if self._tickTask then
		return
	end

	self._tickTask = task.spawn(function()
		while self.state ~= State.DEAD do
			task.wait(1)
			self:Tick()
		end
	end)
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

	-- 確保每秒倒數一定有在跑
	if newState == State.WAITING or newState == State.EATING then
		self:_startTickLoop()
	end

	if newState == State.LEAVING then
		self:_onLeaving()
	end
end

-- 每秒自動跑（由 _startTickLoop 驅動）
function NPC:Tick()
	if self.state == State.DEAD then
		return
	end
	if not self.model then
		self:Destroy()
		return
	end

	-- 每秒更新名字
	self.model.Name = ("%s (%ds)"):format(self.state, math.max(0, self.timer))

	-- WAITING：每秒掃一次碰撞箱找拉麵
	if self.state == State.WAITING then
		self:_tryServe()
	end

	-- 倒數
	if self.timer > 0 then
		self.timer -= 1
	else
		-- WAITING 或 EATING 倒數結束就離開
		if self.state == State.WAITING or self.state == State.EATING then
			self:_setState(State.LEAVING)
		end
	end
end

-- =====================
-- Movement (Safe)
-- =====================

function NPC:_computePath(startPos, goalPos)
	local path = PathfindingService:CreatePath(PATH_PARAMS)
	path:ComputeAsync(startPos, goalPos)
	if path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	return path:GetWaypoints()
end

function NPC:_safeMoveTo(pos)
	if not self.humanoid or not self.humanoid.Parent then
		return false
	end

	local finished = false
	local reached = false

	local conn = self.humanoid.MoveToFinished:Connect(function(ok)
		reached = ok
		finished = true
	end)

	self.humanoid:MoveTo(pos)

	local start = os.clock()
	while not finished and os.clock() - start < MAX_MOVE_TIME do
		task.wait()
	end

	if conn then
		conn:Disconnect()
	end

	return finished and reached
end

function NPC:_followWaypoints(waypoints, onFinish)
	task.spawn(function()
		for i = self.lastWaypointIndex, #waypoints do
			self.lastWaypointIndex = i

			-- NPC 被銷毀或 humanoid 不存在
			if self.state == State.DEAD or not self.humanoid or not self.humanoid.Parent then
				return
			end

			if not self:_safeMoveTo(waypoints[i].Position) then
				self.retryCount += 1
				warn(
					("[NPC %d] Move interrupted (%d/%d) at waypoint %d"):format(self.id, self.retryCount, MAX_RETRY, i)
				)

				if self.retryCount >= MAX_RETRY then
					warn(("[NPC %d] Too many retries -> Destroy"):format(self.id))
					self:Destroy()
					return
				end

				-- 回到上一個 waypoint 再試
				self.lastWaypointIndex = math.max(1, i - 1)
				task.wait(0.5)
				self:_followWaypoints(waypoints, onFinish)
				return
			end
		end

		if onFinish then
			onFinish()
		end
	end)
end

-- =====================
-- Enter / Sit
-- =====================

function NPC:_enterShop()
	local waypoints = self:_computePath(NPCSpawn.Position, self.hitbox.Position)
	if not waypoints then
		self:Destroy()
		return
	end

	self.enterWaypoints = waypoints
	self.lastWaypointIndex = 1
	self.retryCount = 0

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
		self:Destroy()
		return
	end

	-- Motor6D 座位焊接（你指定）
	local weld = Instance.new("Motor6D")
	weld.Name = "SeatWeld"
	weld.Part0 = self.seat
	weld.Part1 = root

	-- 強制定位：把 NPC 對齊到 seat 上方
	local offsetY = (self.seat.Size.Y * 0.5) + (root.Size.Y * 0.5)
	root.CFrame = self.seat.CFrame * CFrame.new(0, offsetY, 0)

	-- Motor6D 的 C0/C1 這裡保持簡單：讓 Part1 以當下相對位置焊住
	-- (讓 root 留在你剛設定的位置)
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

	for _, part in ipairs(parts) do
		local ramenModel = part:FindFirstAncestorOfClass("Model")
		if not ramenModel then
			continue
		end

		if not CollectionService:HasTag(ramenModel, "Ramen") then
			continue
		end
		if ramenModel:GetAttribute("Completed") ~= true then
			continue
		end
		if ramenModel:GetAttribute("BeingDragged") == true then
			continue
		end

		local ramenRoot = ramenModel.PrimaryPart
		if not ramenRoot then
			continue
		end

		-- 若已經焊過（被其他 NPC 吃了），跳過
		if ramenRoot:FindFirstChild("FoodWeld") then
			continue
		end

		-- 爭奪：距離平方更近者可覆蓋 claim
		local myDist2 = dist2(primary.Position, ramenRoot.Position)
		local curNpc = ramenModel:GetAttribute(SERVE_CLAIM_ATTR)
		local curDist = ramenModel:GetAttribute(SERVE_CLAIM_DIST_ATTR)

		if curNpc ~= nil and curNpc ~= self.id and curDist ~= nil and curDist <= myDist2 then
			continue
		end

		ramenModel:SetAttribute(SERVE_CLAIM_ATTR, self.id)
		ramenModel:SetAttribute(SERVE_CLAIM_DIST_ATTR, myDist2)

		-- 用一個 Heartbeat 確認 claim 沒被別人搶走，再正式進入吃飯
		self.claimedFood = ramenModel

		task.spawn(function()
			RunService.Heartbeat:Wait()

			-- NPC 已死 / 不在等待 / claim 被搶走：回復狀態
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

		return
	end
end

function NPC:_eat(ramenModel)
	-- 進入 EATING 前再次確認
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

	-- 若已被焊（別人吃了），放棄
	if ramenRoot:FindFirstChild("FoodWeld") then
		clearServeClaim(ramenModel, self.id)
		if self.claimedFood == ramenModel then
			self.claimedFood = nil
		end
		return
	end

	-- 確定吃飯：WeldConstraint 焊接（你指定）
	local weld = Instance.new("WeldConstraint")
	weld.Name = "FoodWeld"
	weld.Part0 = npcRoot
	weld.Part1 = ramenRoot
	weld.Parent = ramenRoot

	self.food = ramenModel
	self.foodWeld = weld

	-- 吃飯狀態：倒數直接刷新成 20 秒（不管原本剩多少）
	self:_setState(State.EATING, EAT_TIME)
end

-- =====================
-- Leaving / Cleanup
-- =====================

function NPC:_onLeaving()
	if self.state == State.DEAD then
		return
	end

	-- 解除坐姿
	if self.humanoid then
		self.humanoid.Sit = false
	end

	-- 清食物：clear claim + destroy 食物模型（依你原本邏輯）
	if self.food then
		clearServeClaim(self.food, self.id)
		if self.food.Parent then
			self.food:Destroy()
		end
	end
	self.food = nil

	-- 清 claim 記錄（避免 Destroy 時重複處理）
	clearServeClaim(self.claimedFood, self.id)
	self.claimedFood = nil

	-- 清 FoodWeld（焊在 ramenRoot 上，destroy food 時會一起走；這裡保守清空引用）
	self.foodWeld = nil

	-- 清 SeatWeld（Motor6D）
	if self.seatWeld and self.seatWeld.Parent then
		self.seatWeld:Destroy()
	end
	self.seatWeld = nil

	-- 定位回 hitbox 再走回去（你要求）
	local root = self.model and self.model.PrimaryPart
	if not root then
		self:Destroy()
		return
	end

	-- 停止殘留 MoveTo 影響（保守）
	RunService.Heartbeat:Wait()
	root.CFrame = self.hitbox.CFrame
	RunService.Heartbeat:Wait()

	-- 反向路徑回去
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

	-- 清 claim（確保不會卡住別人）
	clearServeClaim(self.claimedFood, self.id)
	clearServeClaim(self.food, self.id)
	self.claimedFood = nil

	-- seat Active 釋放（你系統用的）
	if self.seat then
		self.seat:SetAttribute("Active", false)
	end

	-- 清模型
	if self.model then
		self.model:Destroy()
		self.model = nil
	end

	-- 清引用
	self.humanoid = nil
	self.enterWaypoints = nil
	self.seatWeld = nil
	self.food = nil
	self.foodWeld = nil
	self.serveParams = nil

	setmetatable(self, nil)
end

return NPC

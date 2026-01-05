-- Central scheduler for NPC timers and serving checks.
local NPCManager = {}

local COUNTDOWN_INTERVAL = 1
local SERVE_INTERVAL = 2

local active = {}
local countdownRunning = false
local serveRunning = false

local function pruneIfDead(npc)
	-- Drop destroyed NPCs from the active set.
	if not npc then
		return true
	end
	if getmetatable(npc) == nil or npc.state == "DEAD" then
		active[npc] = nil
		return true
	end
	return false
end

function NPCManager.Register(npc)
	if not npc then
		return
	end
	active[npc] = true
end

function NPCManager.Unregister(npc)
	if not npc then
		return
	end
	active[npc] = nil
end

function NPCManager.Start()
	if not countdownRunning then
		countdownRunning = true
		task.spawn(function()
			while true do
				task.wait(COUNTDOWN_INTERVAL)
				-- Tick countdown on all active NPCs.
				for npc in pairs(active) do
					if not pruneIfDead(npc) then
						npc:TickCountdown()
					end
				end
			end
		end)
	end

	if not serveRunning then
		serveRunning = true
		task.spawn(function()
			while true do
				task.wait(SERVE_INTERVAL)
				-- Periodically check for serving opportunities.
				for npc in pairs(active) do
					if not pruneIfDead(npc) and npc.state == "WAITING_FOOD" then
						npc:TryServe()
					end
				end
			end
		end)
	end
end

return NPCManager

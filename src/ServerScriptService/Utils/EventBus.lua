-- Simple in-memory event bus for local scripts.
local EventBus = {}

local events = {}

function EventBus.on(eventName, callback)
	if not events[eventName] then
		events[eventName] = {}
	end
	table.insert(events[eventName], callback)

	-- Return an unsubscribe function.
	return function()
		for i, cb in ipairs(events[eventName]) do
			if cb == callback then
				table.remove(events[eventName], i)
				break
			end
		end
	end
end

function EventBus.emit(eventName, payload)
	local listeners = events[eventName]
	if not listeners then
		return
	end

	for _, cb in ipairs(table.clone(listeners)) do
		cb(payload)
	end
end

function EventBus.clear()
	events = {}
end

return EventBus

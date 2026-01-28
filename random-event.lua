--========================
--	Random Events (Adventure Mode)
--	- Runs a single random event when called
--	- Can register itself to auto-run via DFHack's "repeat" command
--
--	Commands:
--		random-event once
--		random-event start [ticks]
--		random-event stop
--		random-event interval <ticks>
--========================

--========================
--	Helper functions
--========================
local function calc_box(x, y, z, radius)
	local x1 = x - radius
	local y1 = y - radius

	local x2 = x + radius
	local y2 = y + radius

	return {x=x1, y=y1, z=z}, {x=x2, y=y2, z=z}
end

local function get_adv()
	return dfhack.world.getAdventurer()
end

local function get_nearby_units(pos1, pos2)
	local adv = get_adv()
	if not adv then
		return {}
	end

	local units = dfhack.units.getUnitsInBox(pos1, pos2, function(u)
		return u.id ~= adv.id
	end)

	return units
end

local function get_predator_pool()
	local pool = {}

	for _, raw in ipairs(df.global.world.raws.creatures.all) do
		local f = raw.flags
		local is_pred = f.LARGE_PREDATOR or f.PREDATOR

		if is_pred and not f.SEMIMEGABEAST and not f.MEGABEAST then
			table.insert(pool, raw)
		end
	end

	return pool
end

local function infer_owner_type(unit)
	if dfhack.units.isAnimal(unit) then
		return df.unit_owner_type.PET_MASTER
	else
		return df.unit_owner_type.COMMANDER
	end
end

--========================
--	Event functions
--========================
local function test_event()
	print("A random event occurs!")
	return true
end

-- Placeholder for later expansion
local function animal_attack_event()
	-- Example future direction:
	-- - pick a predator from get_predator_pool()
	-- - spawn it near the adventurer
	-- - assign hostility
	return false
end

local function berserk_event()
	local adv = get_adv()
	if not adv then
		return false
	end

	local pos1, pos2 = calc_box(adv.pos.x, adv.pos.y, adv.pos.z, 6)
	local units = get_nearby_units(pos1, pos2)

	if #units == 0 then
		return false
	end

	local target = units[math.random(#units)]
	target.mood = df.mood_type.Berserk
	return true
end

local function unit_on_fire_event()
	local adv = get_adv()
	if not adv then
		return false
	end

	local pos1, pos2 = calc_box(adv.pos.x, adv.pos.y, adv.pos.z, 6)
	local units = get_nearby_units(pos1, pos2)

	if #units == 0 then
		return false
	end

	local target = units[math.random(#units)]

	for _, entry in ipairs(target.inventory) do
		if entry.item and entry.item.flags then
			entry.item.flags.on_fire = true
		end
	end

	return true
end

--========================
--	New modular events (call other scripts)
--========================
local function random_pregnancy_event()
	-- Default timer (your random-pregnancy.lua defaults to ~9 months)
	-- Runs near adventurer, fails quietly if no candidates
	dfhack.run_command('random-pregnancy --silent --radius 30')
	return true
end

local function instant_baby_event()
	-- Instant baby next tick
	dfhack.run_command('random-pregnancy --silent --radius 30 --timer 1')
	-- or: dfhack.run_command('random-pregnancy --silent --radius 30 --instant')
	return true
end

--========================
--	Event table + runner
--========================
local EVENTS = {
	-- Background-life style events:
	random_pregnancy_event,
	instant_baby_event,

	-- Dramatic events:
	berserk_event,
	unit_on_fire_event,

	--test_event,
	--animal_attack_event,
}

local function run_random_event()
	if #EVENTS == 0 then
		return false
	end

	local event = EVENTS[math.random(#EVENTS)]
	return event() == true
end

--========================
--	Repeat registration helpers (DFHack "repeat" command)
--========================
local REPEAT_NAME = 'random-event'
local DEFAULT_TICKS = 1200	-- adjust to taste (e.g., 800 for ~3 checks/day)

local function repeat_start(ticks)
	ticks = ticks or DEFAULT_TICKS
	dfhack.run_command(('repeat --name %s --time %d --timeUnits ticks --command [ random-event once ]'):format(REPEAT_NAME, ticks))
	print(("Random events: started (every %d ticks)."):format(ticks))
end

local function repeat_stop()
	dfhack.run_command(('repeat --cancel %s'):format(REPEAT_NAME))
	print("Random events: stopped.")
end

--========================
--	Command handling
--========================
local args = {...}
local cmd = args[1]

if cmd == 'once' then
	-- Run exactly one event attempt
	local adv = get_adv()
	if not adv then
		-- Not an error; just means you're not in an adv context right now
		return
	end

	run_random_event()

elseif cmd == 'start' or cmd == nil then
	-- Start repeat loop via DFHack "repeat"
	local ticks = tonumber(args[2]) or DEFAULT_TICKS
	repeat_start(ticks)

elseif cmd == 'interval' and tonumber(args[2]) then
	-- Change interval: stop then start with new ticks
	local ticks = tonumber(args[2])
	repeat_stop()
	repeat_start(ticks)

elseif cmd == 'stop' then
	repeat_stop()

else
	print("Usage:")
	print("  random-event once")
	print("  random-event start [ticks]")
	print("  random-event stop")
	print("  random-event interval <ticks>")
	print("")
	print("Or use DFHack directly:")
	print("  repeat --name random-event --time 1200 --command [ random-event once ]")
end

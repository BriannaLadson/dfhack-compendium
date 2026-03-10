--========================
--	Random Events (Fortress + Adventure)
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
--	Forward declarations (needed for Lua local scoping)
--========================
local ADV_EVENTS
local FORT_EVENTS

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

local function get_event_list()
	if dfhack.world.isAdventureMode() then
		return ADV_EVENTS
	end

	if dfhack.world.isFortressMode() then
		return FORT_EVENTS
	end

	return nil
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

local function get_nearby_units_any(pos1, pos2, exclude_id)
	return dfhack.units.getUnitsInBox(pos1, pos2, function(u)
		return not exclude_id or u.id ~= exclude_id
	end)
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

local function get_fort_active_alive_units()
	local list = {}

	for _, u in ipairs(df.global.world.units.active) do
		if dfhack.units.isAlive(u) then
			table.insert(list, u)
		end
	end

	return list
end

local function get_random_unit()
	local unit = df.global.world.units.active[math.random(#df.global.world.units.active)]

	return unit
end


local function get_all_syndromes()
	local list = {}
	
	for _, syn in ipairs(df.global.world.raws.mat_table.syndromes.all) do
		if #syn.ce > 0 then
			table.insert(list, syn)
		end
		
	end
	
	return list

end

local function get_random_syndrome()
	local all_syndromes = get_all_syndromes()
	
	if #all_syndromes == 0 then
		return nil
	end
	
	local syndrome = all_syndromes[math.random(#all_syndromes)]
	
	return syndrome
end

local function get_unit_name(unit)
	return dfhack.TranslateName(dfhack.units.getVisibleName(unit), true)
end

local function is_nonadult(unit)
	return unit.profession == df.profession.BABY or unit.profession == df.profession.CHILD
end

local function get_party_leader_id(unit)
	if not unit then
		return -1
	end

	local leader_id = unit.relationship_ids[df.unit_relationship_type.GroupLeader]

	if leader_id == -1 then
		return unit.id
	end

	return leader_id
end

local function is_same_party(unit_a, unit_b)
	if not unit_a or not unit_b then
		return false
	end

	return get_party_leader_id(unit_a) == get_party_leader_id(unit_b)
end

local function is_valid_pickpocket_thief(thief, victim)
    if not thief or not victim then
        return false
    end

    -- cannot steal from self
    if thief.id == victim.id then
        return false
    end

    -- prevent children/infants from stealing
    if is_nonadult(thief) then
        return false
    end

    -- prevent party members from stealing from one another
    if is_same_party(thief, victim) then
        return false
    end

    -- basic sanity / existence checks
    if not dfhack.units.isAlive(thief) or not dfhack.units.isAlive(victim) then
        return false
    end

    return true
end

local function get_pickpocketable_inventory(unit)
    local stealable = {}

    for _, inv in ipairs(unit.inventory) do
		if inv.item then
            local mode = inv.mode

            -- Avoid obviously unrealistic steals
            if mode ~= df.inv_item_role_type.Worn
            and mode ~= df.inv_item_role_type.Weapon then
                table.insert(stealable, inv)
            end
        end
    end

    return stealable
end

local function in_adventurer_party(unit)
	local adv = get_adv()
	if not adv or not unit then
		return false
	end

	return is_same_party(unit, adv)
end

local function get_skill(unit, skill)
	local val = dfhack.units.getEffectiveSkill(unit, skill)
	if not val or val < 0 then
		return 0
	end
	return val
end


--========================
--	Event functions
--========================

-- Adventure Mode Events
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

local function berserk_event_adv()
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

local function make_unit_vampire_event_adv()
  local adv = get_adv()
  if not adv then return false end

  local pos1, pos2 = calc_box(adv.pos.x, adv.pos.y, adv.pos.z, 6)
  local units = get_nearby_units(pos1, pos2)
  if #units == 0 then return false end

  for _ = 1, 30 do
    local target = units[math.random(#units)]
    if target and dfhack.units.isAlive(target) then
      if dfhack.units.isHidingCurse(target) or dfhack.units.isBloodsucker(target) then
        goto continue
      end
      if apply_random_syndrome(target, "VAMPIRE") then
        return true
      end
    end
    ::continue::
  end

  return false
end

local function random_unit_syndrome_event_adv()
	local unit = get_random_unit()
	
	local syndrome = get_random_syndrome()
	
	if not unit or not syndrome then
		print(unit)
		print(syndrome)
		
		return false
	end
	
	dfhack.run_command(
		'modtools/add-syndrome',
		'--target', tostring(unit.id),
		'--syndrome', tostring(syndrome.id)
	)
	
	local unit_name = dfhack.units.getReadableName(unit)
	local syn_name = syndrome.syn_name ~= '' and syndrome.syn_name or ("Syndrome ID " .. syndrome.id)
	
	print(unit_name .. " has the syndrome: " .. syn_name)
	
	return true
end

local function unit_on_fire_event_adv()
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

local function random_pickpocket_event_adv()
	--Pickpocket Target
	local target = get_random_unit()
	
	if not target then
		return false
	end
	
	--Pickpocket Thief
	local pos1, pos2 = calc_box(target.pos.x, target.pos.y, target.pos.z, 1)
	
	local units = get_nearby_units(pos1, pos2)
	
	if #units == 0 then
		return false
	end
	
	local possible_thieves = {}
	for _, unit in ipairs(units) do
		if is_valid_pickpocket_thief(unit, target) then
			table.insert(possible_thieves, unit)
		end
	end
	
	if #possible_thieves == 0 then
		return false
	end
	
	local thief = possible_thieves[math.random(#possible_thieves)]
	
	--Pickpocket Item
	local stealable = get_pickpocketable_inventory(target)
	
	if #stealable == 0 then
		return false
	end
	
	local stolen_inv = stealable[math.random(#stealable)]
	local item = stolen_inv.item
	
	local ok = dfhack.items.moveToInventory(
		item,
		thief,
		df.inv_item_role_type.Hauled,
		0
	)
	
	if not ok then
		return false
	end
	
	
	return true
	
end

-- Fortress Mode Events

local function berserk_event_fort()
	local units = get_fort_active_alive_units()
	
	if not units or #units == 0 then
		return false
	end
	
	local target = units[math.random(#units)]
	target.mood = df.mood_type.Berserk
	return true
end


local function make_unit_vampire_event_fort()
  local units = get_fort_active_alive_units()
  if not units or #units == 0 then
    return false
  end

  -- Try multiple times so we don't fail just because we randomly picked an invalid target
  for _ = 1, 30 do
    local target = units[math.random(#units)]

    if target and dfhack.units.isAlive(target) then
      -- Skip existing vampires / hiding curses
      if dfhack.units.isHidingCurse(target) or dfhack.units.isBloodsucker(target) then
        goto continue
      end

      -- Apply any syndrome with syn_class == "VAMPIRE"
      if apply_random_syndrome(target, "VAMPIRE") then
        return true
      end
    end

    ::continue::
  end

  return false
end

local function unit_on_fire_event_fort()
	local units = get_fort_active_alive_units()
	
	if not units or #units == 0 then
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

local function random_unit_syndrome_event_fort()
	local units = get_fort_active_alive_units()
	
	if not units or #units == 0 then
		return false
	end
	
	local unit = units[math.random(#units)]
	
	local syndrome = get_random_syndrome()
	
	if not unit or not syndrome then
		print(unit)
		print(syndrome)
		
		return false
	end
	
	dfhack.run_command(
		'modtools/add-syndrome',
		'--target', tostring(unit.id),
		'--syndrome', tostring(syndrome.id)
	)
	
	local unit_name = dfhack.units.getReadableName(unit)
	local syn_name = syndrome.syn_name ~= '' and syndrome.syn_name or ("Syndrome ID " .. syndrome.id)
	
	print(unit_name .. " has the syndrome: " .. syn_name)
	
	return true
end

local function random_pickpocket_event_fort()
	local units = get_fort_active_alive_units()
	if not units or #units == 0 then
		return false
	end

	local target = units[math.random(#units)]
	
	local pos1, pos2 = calc_box(target.pos.x, target.pos.y, target.pos.z, 1)
	local nearby = get_nearby_units_any(pos1, pos2, target.id)

	if #nearby == 0 then
		return false
	end

	local possible_thieves = {}
	for _, unit in ipairs(nearby) do
		if is_valid_pickpocket_thief(unit, target) then
			table.insert(possible_thieves, unit)
		end
	end

	if #possible_thieves == 0 then
		return false
	end

	local thief = possible_thieves[math.random(#possible_thieves)]
	local stealable = get_pickpocketable_inventory(target)

	if #stealable == 0 then
		return false
	end

	local stolen_inv = stealable[math.random(#stealable)]
	local item = stolen_inv.item

	return dfhack.items.moveToInventory(item, thief, df.inv_item_role_type.Hauled, 0) or false
end
--========================
--	New modular events (call other scripts)
--========================
local function random_pregnancy_event_adv()
	-- Runs your other script; should be mode-safe (if not, split into _adv/_fort versions)
	dfhack.run_command('random-pregnancy --silent --radius 30')
	return true
end

local function random_pregnancy_event_fort()
	-- Runs your other script; should be mode-safe (if not, split into _adv/_fort versions)
	dfhack.run_command('random-pregnancy --silent --global')
	return true
end

local function instant_baby_event_adv()
	dfhack.run_command('random-pregnancy --silent --radius 30 --timer 1')
	return true
end

local function instant_baby_event_fort()
	dfhack.run_command('random-pregnancy --silent --global --timer 1')
	return true
end

--========================
--	Event tables
--========================
ADV_EVENTS = {
	random_pregnancy_event_adv,
	instant_baby_event_adv,
	berserk_event_adv,
	unit_on_fire_event_adv,
	make_unit_vampire_event_adv,
	random_unit_syndrome_event_adv,
	random_pickpocket_event_adv,
}

FORT_EVENTS = {
	random_pregnancy_event_fort,
	instant_baby_event_fort,
	berserk_event_fort,
	unit_on_fire_event_fort,
	make_unit_vampire_event_fort,
	random_unit_syndrome_event_fort,
	random_pickpocket_event_fort, --Needs to be tested!
}

--========================
--	Event runner
--========================
local function run_random_event(events)
	if not events or #events == 0 then
		return false
	end

	local event = events[math.random(#events)]
	return event() == true
end

--========================
--	Repeat registration helpers (DFHack "repeat" command)
--========================
local REPEAT_NAME = 'random-event'
local DEFAULT_TICKS = 1200 -- fortress-day-ish; override per-mode by passing ticks if desired

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
	-- Run exactly one event attempt (fort OR adv)
	local events = get_event_list()
	if not events then
		-- Not in a loaded fort/adv context right now
		return
	end

	run_random_event(events)

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

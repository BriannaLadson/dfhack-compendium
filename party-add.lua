-- party-add.lua
-- Select a unit, run `party-add`, and it will:
-- - set GroupLeader = adventurer.id (so they follow as a companion)
-- - if animal/tamable, set PetOwner = adventurer.id
-- - also sets unit.following (if present) for immediate follow
-- - ensures the unit is listed in the Adventure Mode party structures (animals + non-animals)
-- - re-applies after every map load (fast travel -> local map, etc.)
-- - runs `advtools pets` to fix DF bookkeeping so pets/companions don't "go home"/get lost

local PERSIST_KEY = "party_add_follow_ids"

-------------------------
-- Persistence helpers
-------------------------
local function get_entry()
	local ok, entry = pcall(function()
		local e = dfhack.persistent.get(PERSIST_KEY)
		if not e then
			e = dfhack.persistent.save({ key=PERSIST_KEY, value="" })
		end
		return e
	end)
	if not ok then
		return nil
	end
	return entry
end

local function parse_ids(s)
	local ids = {}
	local seen = {}
	if not s or s == "" then return ids, seen end
	for part in tostring(s):gmatch("[^,]+") do
		local n = tonumber(part)
		if n and n >= 0 and not seen[n] then
			table.insert(ids, n)
			seen[n] = true
		end
	end
	return ids, seen
end

local function ids_to_string(ids)
	return table.concat(ids, ",")
end

local function load_ids()
	local entry = get_entry()
	if not entry then
		return {}, {}
	end
	return parse_ids(entry.value)
end

local function save_ids(ids)
	local entry = get_entry()
	if not entry then
		return false
	end
	entry.value = ids_to_string(ids)
	return true
end

-------------------------
-- Relationship helpers
-------------------------
local function rel_idx(name)
	return df.unit_relationship_type[name]
		or df.unit_relationship_type[name:lower()]
		or (name == "PetOwner" and (df.unit_relationship_type.PetOwner or df.unit_relationship_type["PetOwner"] or df.unit_relationship_type["pet_owner"]))
		or (name == "GroupLeader" and (df.unit_relationship_type.GroupLeader or df.unit_relationship_type["GroupLeader"] or df.unit_relationship_type["group_leader"]))
end

local function set_rel(unit, rel_name, value)
	if not unit or not unit.relationship_ids then return false end
	if not df.unit_relationship_type then return false end
	local idx = rel_idx(rel_name)
	if not idx then return false end
	if idx >= 0 and idx < #unit.relationship_ids then
		unit.relationship_ids[idx] = value
		return true
	end
	return false
end

local function is_animal_tamable(unit)
	local ok, res = pcall(function()
		return dfhack.units.isTamable(unit)
	end)
	return ok and res
end

local function apply_follow_links(unit, adv)
	if not unit or not adv then return end

	-- Everyone gets a group leader (non-animals too)
	set_rel(unit, "GroupLeader", adv.id)

	-- Only animals (tamable) get pet owner
	if is_animal_tamable(unit) then
		set_rel(unit, "PetOwner", adv.id)
	end

	-- Immediate follow on the currently loaded map (if field exists in your build)
	if unit.following ~= nil then
		unit.following = adv.id
	end
end

-------------------------
-- Adventure party helpers
-------------------------
local function vec_contains(vec, id)
	if not vec then return false end
	for _, v in ipairs(vec) do
		if v == id then return true end
	end
	return false
end

local function vec_add(vec, id)
	if not vec or id == nil then return false end
	if vec_contains(vec, id) then return true end
	-- DFHack vectors support insert('#', value)
	if vec.insert then
		vec:insert('#', id)
		return true
	end
	return false
end

local function ensure_in_adv_party(unit, adv)
	-- Best-effort across DF/DFHack builds:
	-- - Non-animals should be in a party members/companions vector (if present)
	-- - Animals should also be in party_pets (if present)
	local advg = df.global.adventure
	if not advg then return end
	local inter = advg.interactions
	if not inter then return end

	-- Common vectors for "companions" across versions/mods
	local member_vecs = {
		'inter.party_members',
		'inter.party_companions',
		'inter.party_units',
		'inter.party', -- sometimes used as a units list
		'inter.companions',
		'inter.followers',
		'inter.party_followers',
	}

	local added_any = false

	-- Resolve strings like 'inter.party_members' safely
	for _, path in ipairs(member_vecs) do
		local ok, vec = pcall(function()
			local key = path:match("^inter%.(.+)$")
			return key and inter[key] or nil
		end)
		if ok and vec then
			-- Only insert into integer vectors (heuristic: vec[0] exists or insert method exists)
			if vec.insert then
				if vec_add(vec, unit.id) then
					added_any = true
				end
			end
		end
	end

	-- Animals also go in party_pets if it exists
	if is_animal_tamable(unit) then
		local ok, pets = pcall(function() return inter.party_pets end)
		if ok and pets and pets.insert then
			if vec_add(pets, unit.id) then
				added_any = true
			end
		end
	end

	-- (Optional) you can print when nothing matched, but keep script quiet by default
	-- if not added_any then print("party-add: note: no known party vectors found to record companion.") end
end

local function fix_adv_pets()
	-- DFHack helper that fixes adventure-mode pet bookkeeping so pets don't "go home"/get lost.
	pcall(function()
		dfhack.run_command_silent('advtools pets')
	end)
end

-------------------------
-- Re-apply on map load
-------------------------
local function relink_all_tracked()
	local adv = dfhack.world.getAdventurer()
	if not adv then return end

	local ids = load_ids()
	for _, id in ipairs(ids) do
		local u = df.unit.find(id)
		if u then
			apply_follow_links(u, adv)
			ensure_in_adv_party(u, adv)
		end
	end

	-- Let DFHack repair any lingering bookkeeping
	fix_adv_pets()
end

-- Register handler once
if not dfhack.onStateChange.party_add_relink then
	dfhack.onStateChange.party_add_relink = function(code)
		-- Fires when local map is loaded (includes after fast travel)
		if code == SC_MAP_LOADED then
			relink_all_tracked()
		end
	end
end

-------------------------
-- Command handling
-------------------------
local args = {...}
local sub = args[1]

local function cmd_list()
	local ids = load_ids()
	if #ids == 0 then
		print("party-add: (empty)")
		return
	end
	print("party-add tracked unit ids:")
	for _, id in ipairs(ids) do
		print(" - " .. tostring(id))
	end
end

local function cmd_clear()
	save_ids({})
	print("party-add: cleared tracked list.")
end

local function cmd_remove_selected()
	local unit = dfhack.gui.getSelectedUnit()
	if not unit then qerror("Select a unit to remove.") end

	local ids, seen = load_ids()
	if not seen[unit.id] then
		print("party-add: unit " .. unit.id .. " was not tracked.")
		return
	end

	local new_ids = {}
	for _, id in ipairs(ids) do
		if id ~= unit.id then table.insert(new_ids, id) end
	end
	save_ids(new_ids)
	print("party-add: removed unit " .. unit.id .. " from tracked list.")
end

local function cmd_add_selected()
	local unit = dfhack.gui.getSelectedUnit()
	if not unit then qerror("Select a unit to add.") end

	local adv = dfhack.world.getAdventurer()
	if not adv then qerror("This can only be run in Adventure Mode.") end

	local ids, seen = load_ids()
	if not seen[unit.id] then
		table.insert(ids, unit.id)
		save_ids(ids)
	end

	apply_follow_links(unit, adv)
	ensure_in_adv_party(unit, adv)

	-- Repair DF bookkeeping (helps prevent "going home"/getting lost)
	fix_adv_pets()

	print(("party-add: linked unit %d to adv %d. (GroupLeader set%s)")
		:format(unit.id, adv.id, is_animal_tamable(unit) and ", PetOwner set" or ""))
end

if sub == "list" then
	cmd_list()
elseif sub == "clear" then
	cmd_clear()
elseif sub == "remove" then
	cmd_remove_selected()
else
	cmd_add_selected()
end

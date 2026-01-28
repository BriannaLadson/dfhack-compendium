-- party-remove.lua
-- Select a unit and run `party-remove` to stop it from following you.

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
	if not ok then return nil end
	return entry
end

local function parse_ids(s)
	local ids = {}
	if not s or s == "" then return ids end
	for part in tostring(s):gmatch("[^,]+") do
		local n = tonumber(part)
		if n and n >= 0 then
			table.insert(ids, n)
		end
	end
	return ids
end

local function save_ids(ids)
	local entry = get_entry()
	if not entry then return false end
	entry.value = table.concat(ids, ",")
	return true
end

local function fix_adv_pets()
	-- DFHack helper that fixes adventure-mode pet bookkeeping so pets don't "go home"/get lost.
	pcall(function()
		dfhack.run_command_silent('advtools pets')
	end)
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

local function clear_rel(unit, rel_name)
	if not unit or not unit.relationship_ids then return end
	if not df.unit_relationship_type then return end

	local idx = rel_idx(rel_name)
	if not idx then return end
	if idx >= 0 and idx < #unit.relationship_ids then
		unit.relationship_ids[idx] = -1
	end
end

-------------------------
-- Main
-------------------------
local unit = dfhack.gui.getSelectedUnit()
if not unit then
	qerror("Select a unit to remove from your party.")
end

-- Clear follow relationships
clear_rel(unit, "GroupLeader")
clear_rel(unit, "PetOwner")

-- Clear immediate follow (if present)
if unit.following ~= nil then
	unit.following = -1
end

-- Remove from persistent follow list
local entry = get_entry()
if entry then
	local ids = parse_ids(entry.value)
	local new_ids = {}
	for _, id in ipairs(ids) do
		if id ~= unit.id then
			table.insert(new_ids, id)
		end
	end
	save_ids(new_ids)
end

print(("party-remove: unit %d removed from party."):format(unit.id))


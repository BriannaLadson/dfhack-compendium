local DEFAULT_TICKS = 1

local WEAPON_SKILLS = {
    df.job_skill.AXE,
    df.job_skill.SWORD,
    df.job_skill.DAGGER,
    df.job_skill.MACE,
    df.job_skill.HAMMER,
    df.job_skill.SPEAR,
    df.job_skill.CROSSBOW,
    df.job_skill.PIKE,
    df.job_skill.WHIP,
    df.job_skill.BOW,
    df.job_skill.BLOWGUN,
    --df.job_skill.SHIELD,
    --df.job_skill.ARMOR,
}

-- Helper Functions
local function get_adv()
	return dfhack.world.getAdventurer()
end

local function get_all_party_members()
	local party = df.global.adventure.interactions
	local members = {}
	local adv = get_adv()
	
	local function add_member(histfig_id)
		local hf = df.historical_figure.find(histfig_id)
		
		if not hf then return end
		
		local unit = df.unit.find(hf.unit_id)
		if not unit then return end
		
		if unit.flags2.killed then return end
		
		if unit == adv then return end
		
		table.insert(members, unit)
	end
	
	for _, id in ipairs(party.party_core_members) do
		add_member(id)
	end
	
	for _, id in ipairs(party.party_extra_members) do
		add_member(id)
	end
	
	return members
end

local function get_unit_inventory_items(unit)
	local items = {}
	
	if not unit or not unit.inventory then
		return items
	end
	
	for _, inv in ipairs(unit.inventory) do
		local item = inv.item
		
		if item then
			table.insert(items, {
				item = item,
				mode = inv.mode,
			})
		end
	end
	
	return items
end

local function get_skill_level(unit, target_skill)
	local soul = unit.status.current_soul
	
	if not soul then return 0 end
	
	for _, skill in ipairs(soul.skills) do
		if skill.id == target_skill then
			return skill.rating
		end
	end
	
	return 0
end

local function get_best_weapon_skill(unit)
	if not unit.status or not unit.status.current_soul then
		return nil, 0
	end
	
	local best_skill = nil
	local best_level = -1
	
	for _, skill in ipairs(WEAPON_SKILLS) do
		local level = get_skill_level(unit, skill)
		
		if level > best_level then
			best_level = level
			best_skill = skill
		end
	end
			
	if best_level <= 0 then
		return nil, 0
	end
		
	return best_skill, best_level
end

local function is_weapon(item)
    return item and item:getType() == df.item_type.WEAPON
end

local function get_weapons_from_inventory(inventory)
    local weapons = {}

    for _, entry in ipairs(inventory) do
        local item = entry.item
        if is_weapon(item) then
            table.insert(weapons, item)
        end
    end

    return weapons
end

local function get_weapon_skill_from_item(item)
	if not item then return nil end

    if item:getType() ~= df.item_type.WEAPON then
        return nil
    end

    local def = item.subtype
    if not def then return nil end

    if def.skill_melee == nil then
        return nil
    end
	
	print(item.subtype)
	print(item.subtype.id)

    return def.skill_melee
end

local function filter_weapons_by_skill(weapons, weapon_skill)
    local matches = {}

    for _, item in ipairs(weapons) do
        local skill = get_weapon_skill_from_item(item)

        if skill == weapon_skill then
            table.insert(matches, item)
        end
    end

    return matches
end

local function collect_item_recursive(item, out)
    if not item then return end

    table.insert(out, item)

    local contained = dfhack.items.getContainedItems(item)

    if contained then
        for _, child in ipairs(contained) do
            collect_item_recursive(child, out)
        end
    end
end

local function get_all_unit_items(unit)
    local items = {}

    if not unit or not unit.inventory then
        return items
    end

    for _, inv in ipairs(unit.inventory) do
        local item = inv.item
        if item then
            collect_item_recursive(item, items)
        end
    end

    return items
end

local function get_weapon_material(item)
    if not item then return nil end

    local mat = dfhack.matinfo.decode(item)
    if not mat or not mat.material then return nil end

    return mat
end

local function safe_get_density(mat)
    if not mat or not mat.material then return 1 end

    local m = mat.material

    if m.state and m.state.solids and m.state.solids[0] then
        local d = m.state.solids[0].density
        if d then return d / 1000 end
    end

    return 1
end

local function safe_get(mat, field)
    if not mat or not mat.material then return 0 end

    local val = mat.material[field]
    if val == nil then return 0 end

    return val
end

local function get_matinfo(item)
    if not item then return nil end
    return dfhack.matinfo.decode(item)
end

local function mat_stat(mat, field, strain_type)
    if not mat or not mat.material then return 0 end

    local m = mat.material

    -- strength fields are nested
    if field == "strength_yield" then
        return (m.strength and m.strength.yield and m.strength.yield[strain_type]) or 0
    elseif field == "strength_fracture" then
        return (m.strength and m.strength.fracture and m.strength.fracture[strain_type]) or 0
    end

    return 0
end

local function mat_density(mat)
    if not mat or not mat.material then return 1 end

    local m = mat.material

    -- DFHack provides density directly
    if m.solid_density then
        return m.solid_density / 1000
    end

    return 1
end

local function get_weapon_size(item)
    if not item then return 1 end

    local wt = df.global.world.raws.itemdefs.weapons[item.subtype]
    if wt and wt.size then
        return wt.size
    end

    return 1
end

local function score_weapon(item, unit)
    if not item then return -math.huge end
    if item:getType() ~= df.item_type.WEAPON then return -math.huge end

    local mat = dfhack.matinfo.decode(item)
    if not mat or not mat.material then return -math.huge end

    local m = mat.material

    -- material stats
    local function yield(strain)
        return (m.strength and m.strength.yield and m.strength.yield[strain]) or 0
    end

    local function fracture(strain)
        return (m.strength and m.strength.fracture and m.strength.fracture[strain]) or 0
    end

    local shear_fracture = fracture(df.strain_type.SHEAR)
    local impact_yield = yield(df.strain_type.IMPACT)

    local density = (m.solid_density and m.solid_density / 1000) or 1
    local size = item.subtype.size or 1

    -- attack analysis
    local attacks = item.subtype.attacks or {}

    local best_score = 0

    for _, atk in ipairs(attacks) do
        local vel = atk.velocity_mult or 1
        local contact = atk.contact or 1
        local penetration = atk.penetration or 1

        local is_edged = atk.edged

        local score = 0

        if is_edged then
            -- EDGE / PIERCE → favor sharp materials (steel)
            score = (shear_fracture * penetration * vel) / contact
        else
            -- BLUNT → favor heavy materials (silver, dense)
            score = density * size * vel * impact_yield
        end

        if score > best_score then
            best_score = score
        end
    end

    return best_score
end

local function is_equipped_weapon(entry)
    if not entry or not entry.item then return false end

    -- DFHack inventory modes: wielded items are typically mode 0 (or "Weapon")
    -- Safer check is mode-based + type check
    return is_weapon(entry.item) and entry.mode == df.unit_inventory_item.T_mode.Worn or
           entry.mode == df.unit_inventory_item.T_mode.Weapon
end

local function get_equipped_weapon(unit)
    if not unit or not unit.inventory then return nil end

    for _, inv in ipairs(unit.inventory) do
        if is_weapon(inv.item) then
            if inv.mode == 1 then
                return inv.item
            end
        end
    end

    return nil
end

local function unequip_item(unit, item)
    if not unit or not item then return end

    -- safest DFHack removal method
    dfhack.items.remove(item)
end

local function equip_item(unit, item)
    if not unit or not item then return end

    -- DFHack API handles equip via assignment
    dfhack.items.moveToInventory(item, unit, 1)
end

local function is_equipped_weapon(inv)
    if not inv or not inv.item then return false end
    if not is_weapon(inv.item) then return false end

    local mode = inv.mode
    return mode == df.unit_inventory_item.T_mode.Weapon
end

local function strip_extra_weapons(unit, keep_item)
    if not unit or not unit.inventory then return end

    local to_remove = {}

    -- STEP 1: collect items safely
    for _, inv in ipairs(unit.inventory) do
        local item = inv.item

        if is_weapon(item) and item ~= keep_item then
            if inv.mode == 1 then
                table.insert(to_remove, item)
            end
        end
    end

    -- STEP 2: mutate AFTER iteration
    for _, item in ipairs(to_remove) do
        dfhack.items.moveToGround(item, unit.pos)
    end
end

local function get_ground_weapons(unit)
    local x, y, z = unit.pos.x, unit.pos.y, unit.pos.z
    local weapons = {}

    for _, item in ipairs(df.global.world.items.other) do
        if is_weapon(item) then
            local pos = dfhack.items.getPosition(item)

            if pos and pos.x == x and pos.y == y and pos.z == z then
                table.insert(weapons, item)
            end
        end
    end

    return weapons
end

local function debug_weapon_skills(unit)
    local name = dfhack.units.getReadableName(unit)
    print("---- " .. name .. " ----")
    
    for _, skill in ipairs(WEAPON_SKILLS) do
        local level = get_skill_level(unit, skill)
        
        if level > 0 then
            local skill_name = df.job_skill.attrs[skill].caption
            print(skill_name .. ": " .. level)
        end
    end
end

local function test()
	local members = get_all_party_members()
	
	for _, unit in ipairs(members) do
		local skill, level = get_best_weapon_skill(unit)
		
		local name = dfhack.units.getReadableName(unit)
		
		if skill then
			local skill_name = df.job_skill.attrs[skill].caption
			print(string.format("%s -> Best Skill: %s (%d)", name, skill_name, level))
		else
			print(string.format("%s -> No dominant weapon skill", name))
		end
		
		debug_weapon_skills(unit)
		
	end
end


--Dynamic Party
local function evaluate_equipment(npc)
	if not npc or not npc.inventory then return end
	
	local inventory = get_unit_inventory_items(npc)
	
	equip_best_weapon(npc, inventory)
end

local function evaluate_weapon(unit, item)
	return score_weapon(item, unit)
end

function equip_best_weapon(unit, inventory)
    local best_item = nil
    local best_score = -math.huge

    for _, entry in ipairs(inventory) do
        local item = entry.item

        if is_weapon(item) then
            local score = evaluate_weapon(unit, item)

            if score > best_score then
                best_score = score
                best_item = item
            end
        end
    end

    if not best_item then return end

    local current = get_equipped_weapon(unit)

    -- already using best weapon → do nothing
    if current == best_item then
        strip_extra_weapons(unit, best_item)
    end

    -- unequip current weapon
    if current then
        unequip_item(unit, current)
    end

    -- equip new weapon
    equip_item(unit, best_item)
	
	-- REMOVE other equipped weapons
	strip_extra_weapons(unit, best_item)

    print(dfhack.units.getReadableName(unit) ..
        " EQUIPPED: " ..
        dfhack.items.getReadableDescription(best_item))
end

-- Repetition
local function repeat_start(ticks)
	ticks = ticks or DEFAULT_TICKS
	
	dfhack.run_command(('repeat --name %s --time %d --timeUnits ticks --command [ dynamic-party once ]'):format("dynamic-party", ticks))
end

local function repeat_stop()
	dfhack.run_command(('repeat --cancel %s'):format("dynamic-party"))
end

-- Runner
local function run_dynamic_party()
    local members = get_all_party_members()

    for _, unit in ipairs(members) do
        evaluate_equipment(unit)
    end
end

-- Commands
local args = {...}
local cmd = args[1]

if cmd == 'once' then
	run_dynamic_party()
	
elseif cmd == 'start' or cmd == nil then
	local ticks = tonumber(args[2]) or DEFAULT_TICKS
	repeat_start(ticks)
	
elseif cmd == 'stop' then
	repeat_stop()
end
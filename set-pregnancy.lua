--@ module = true

local DEFAULT_GESTATION_TIMER = 1

local function get_unit_name(unit)
    if not unit then return 'Unknown unit' end

    local ok, name = pcall(function()
        return dfhack.units.getReadableName(unit)
    end)

    if ok and name and name ~= '' then
        return name
    end

    return 'Unit #' .. tostring(unit.id)
end

local function is_valid_parent(unit)
    return unit ~= nil
        and dfhack.units.isAdult(unit)
        and not dfhack.units.isAnimal(unit)
end

local function get_biological_pair(unit1, unit2)
    if not unit1 or not unit2 then
        return nil, nil, 'Missing unit.'
    end

    if dfhack.units.isMale(unit1) and dfhack.units.isFemale(unit2) then
        return unit1, unit2, nil
    end

    if dfhack.units.isFemale(unit1) and dfhack.units.isMale(unit2) then
        return unit2, unit1, nil
    end

    return nil, nil, 'Selected unit and adventurer must be a male/female pair.'
end

function set_pregnancy(female, male, gestation_timer)
    if not female then
        return false, 'No female unit provided.'
    end

    if not male then
        return false, 'No male unit provided.'
    end

    if not is_valid_parent(female) then
        return false, 'Female unit is not a valid sentient adult target.'
    end

    if not is_valid_parent(male) then
        return false, 'Male unit is not a valid sentient adult target.'
    end

    if not dfhack.units.isFemale(female) then
        return false, 'Mother unit must be female.'
    end

    if not dfhack.units.isMale(male) then
        return false, 'Father unit must be male.'
    end

    local timer = tonumber(gestation_timer) or DEFAULT_GESTATION_TIMER

    if timer < 1 then
        return false, 'Gestation timer must be 1 or higher.'
    end

    local current_timer = tonumber(female.pregnancy_timer) or 0

	if current_timer > 0 then
		return false, get_unit_name(female) .. ' is already pregnant.'
	end

    female.pregnancy_timer = timer
    female.pregnancy_caste = male.caste
    female.pregnancy_spouse = male.hist_figure_id or -1

    female.pregnancy_genes = df.unit_genes:new()
    female.pregnancy_genes:assign(male.appearance.genes)

    return true, get_unit_name(female) .. ' may be expecting a child.'
end

function set_pregnancy_for_pair(unit1, unit2, gestation_timer)
    if not unit1 or not unit2 then
        return false, 'No valid units selected.'
    end

    if unit1.id == unit2.id then
        return false, 'Cannot create pregnancy from one unit.'
    end

    if not is_valid_parent(unit1) then
        return false, get_unit_name(unit1) .. ' is not a valid sentient adult target.'
    end

    if not is_valid_parent(unit2) then
        return false, get_unit_name(unit2) .. ' is not a valid sentient adult target.'
    end

    local male, female, err = get_biological_pair(unit1, unit2)

    if not male or not female then
        return false, err
    end

    return set_pregnancy(female, male, gestation_timer)
end

local function main(...)
    local selected = dfhack.gui.getSelectedUnit(true)

    if not selected then
        qerror('No unit is selected.')
    end

    local adv = dfhack.world.getAdventurer()

    if not adv then
        qerror('No valid adventurer.')
    end

    local args = {...}
    local gestation_timer = tonumber(args[1]) or DEFAULT_GESTATION_TIMER

    local ok, message = set_pregnancy_for_pair(selected, adv, gestation_timer)

    if not ok then
        qerror(message)
    end

    print(message)
end

if not dfhack_flags.module then
    main(...)
end

return {
    set_pregnancy = set_pregnancy,
    set_pregnancy_for_pair = set_pregnancy_for_pair,
}
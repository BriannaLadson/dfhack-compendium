-- romance-quests.lua

local gui = require('gui')
local widgets = require('gui.widgets')
local json = require('json')
local setorientation = dfhack.reqscript('set-orientation')
local setpregnancy = dfhack.reqscript('set-pregnancy')

local ACTIVE_QUESTS = {}
local CANCEL_PENALTY = 5
local COMPLETE_REWARD = 10
local SPEND_NIGHT_REJECTION_PENALTY = 1
local SPEND_NIGHT_REWARD = 1
local SPEND_NIGHT_PREGNANCY_CHANCE = 20
local TICKS_PER_DAY = 1200
local TICKS_PER_MONTH = 28 * TICKS_PER_DAY
local STANDARD_GESTATION_TICKS = 9 * TICKS_PER_MONTH
local PERSIST_KEY = 'romance-quests'

-------------------------------------------------
-- Text Safety
-------------------------------------------------

local function safe_text(value)
    value = tostring(value or '')
    value = value:gsub('[^\032-\126]', '?')
    return value
end

-------------------------------------------------
-- Save / Load
-------------------------------------------------

local function sanitize_quest(quest)
    return {
        quest_key = safe_text(quest.quest_key),
        type = safe_text(quest.type),

        target_id = tonumber(quest.target_id) or -1,
        target_hfid = tonumber(quest.target_hfid) or -1,

        item_type = tonumber(quest.item_type) or -1,
        item_subtype = tonumber(quest.item_subtype) or -1,
        item_name = safe_text(quest.item_name),

        display_name = safe_text(quest.display_name),

        reaction_code = safe_text(quest.reaction_code),
        reaction_name = safe_text(quest.reaction_name),

        completed = quest.completed == true,

        message = quest.message and safe_text(quest.message) or nil,
    }
end

local function sanitize_quest_list(data)
    local quests = {}

    if type(data) ~= 'table' then
        return quests
    end

    for _, quest in ipairs(data) do
        if type(quest) == 'table' then
            table.insert(quests, sanitize_quest(quest))
        end
    end

    return quests
end

local function load_quests()
    local ok, state = pcall(function()
        return dfhack.persistent.getWorldData(PERSIST_KEY, {
            quests = {}
        })
    end)

    if not ok or type(state) ~= 'table' then
        print('Failed to load romance quest persistent data.')
        print('You may need to run:')
        print("lua dfhack.persistent.deleteWorldData('romance-quests')")
        ACTIVE_QUESTS = {}
        return
    end

    ACTIVE_QUESTS = sanitize_quest_list(state.quests or {})
    print('Loaded romance quest count: ' .. tostring(#ACTIVE_QUESTS))
end

local function save_quests()
    ACTIVE_QUESTS = sanitize_quest_list(ACTIVE_QUESTS)

    dfhack.persistent.saveWorldData(PERSIST_KEY, {
        quests = ACTIVE_QUESTS
    })

    print('Romance quests saved to DFHack persistent world data.')
    print('Quest count: ' .. tostring(#ACTIVE_QUESTS))

    return true
end

-------------------------------------------------
-- Quest Helpers
-------------------------------------------------

local function find_quest_index(key)
    key = safe_text(key)

    for i, quest in ipairs(ACTIVE_QUESTS) do
        if safe_text(quest.quest_key) == key then
            return i
        end
    end

    return nil
end

local function get_quest(key)
    local i = find_quest_index(key)

    if i then
        return ACTIVE_QUESTS[i]
    end

    return nil
end

local function set_quest(key, quest)
    if not key then
        print('Cannot save quest. Quest key is nil.')
        return false
    end

    quest.quest_key = safe_text(key)
    quest = sanitize_quest(quest)

    local i = find_quest_index(key)

    if i then
        ACTIVE_QUESTS[i] = quest
    else
        table.insert(ACTIVE_QUESTS, quest)
    end

    print('Quest saved in memory: ' .. tostring(quest.quest_key))
    print('Active quest count: ' .. tostring(#ACTIVE_QUESTS))

    return true
end

local function remove_quest(key)
    local i = find_quest_index(key)

    if i then
        table.remove(ACTIVE_QUESTS, i)
        print('Quest removed: ' .. tostring(key))
    end
end

-------------------------------------------------
-- Utility Functions
-------------------------------------------------

local function get_selected_unit()
    return dfhack.gui.getSelectedUnit(true)
end

local function get_adventurer()
    return dfhack.world.getAdventurer()
end

local function get_unit_name(unit)
    if not unit then return 'No NPC Selected' end
    return dfhack.units.getReadableName(unit)
end

local function get_safe_unit_name(unit)
    return safe_text(get_unit_name(unit))
end

local function get_quest_key(unit1, unit2)
    if not unit1 or not unit2 then return nil end
    if not unit1.hist_figure_id or not unit2.hist_figure_id then return nil end
    if unit1.hist_figure_id < 0 or unit2.hist_figure_id < 0 then return nil end

    return tostring(unit1.hist_figure_id) .. ':' .. tostring(unit2.hist_figure_id)
end

-------------------------------------------------
-- Relationship Helpers
-------------------------------------------------

local function clamp_relationship_strength(value)
    return math.max(0, math.min(100, tonumber(value) or 0))
end

local function get_hf(unit)
    if not unit then return nil end
    if not unit.hist_figure_id or unit.hist_figure_id < 0 then return nil end
    return df.historical_figure.find(unit.hist_figure_id)
end


local function is_adult_and_sane(unit)
    return unit ~= nil
        and dfhack.units.isAdult(unit)
        and dfhack.units.isSane(unit)
end

local function get_orientation_interest(unit, target)
    if not unit or not target then
        return 0
    end

    if not unit.status
        or not unit.status.current_soul
        or not unit.status.current_soul.orientation_flags
    then
        return 0
    end

    if target.sex == df.pronoun_type.he or tonumber(target.sex) == 1 then
        return setorientation.getInterest(unit, 'male')
    elseif target.sex == df.pronoun_type.she or tonumber(target.sex) == 0 then
        return setorientation.getInterest(unit, 'female')
    end

    return 0
end

local function can_start_lover_relationship(unit1, unit2)
    if not unit1 or not unit2 then
        return false, 'No valid units selected.'
    end

    if unit1.id == unit2.id then
        return false, 'You cannot romance yourself.'
    end

    if not is_adult_and_sane(unit1) then
        return false, 'The adventurer must be an adult and sane.'
    end

    if not is_adult_and_sane(unit2) then
        return false, 'The NPC must be an adult and sane.'
    end

    local interest1 = get_orientation_interest(unit1, unit2)
    local interest2 = get_orientation_interest(unit2, unit1)

    if interest1 < 1 then
        return false, 'The adventurer is not romantically interested in this NPC\'s sex.'
    end

    if interest2 < 1 then
        return false, 'The NPC is not romantically interested in the adventurer\'s sex.'
    end

    return true, 'Romance-compatible.'
end

local function can_marry_units(unit1, unit2)
    local ok, message = can_start_lover_relationship(unit1, unit2)

    if not ok then
        return false, message
    end

    local interest1 = get_orientation_interest(unit1, unit2)
    local interest2 = get_orientation_interest(unit2, unit1)

    if interest1 < 2 then
        return false, 'The adventurer is open to romance, but not marriage with this NPC\'s sex.'
    end

    if interest2 < 2 then
        return false, 'The NPC is open to romance, but not marriage with the adventurer\'s sex.'
    end

    return true, 'Marriage-compatible.'
end

local function get_hf_link(unit1, unit2, link_type)
    if not unit1 or not unit2 or not link_type then return nil end

    local hf1 = get_hf(unit1)
    if not hf1 then return nil end

    for _, link in ipairs(hf1.histfig_links) do
        if link._type == link_type
            and link.target_hf == unit2.hist_figure_id
        then
            return link
        end
    end

    return nil
end


local function remove_hf_link(unit1, unit2, link_type)
    if not unit1 or not unit2 or not link_type then return false end

    local hf1 = get_hf(unit1)
    if not hf1 then return false end

    for i = #hf1.histfig_links - 1, 0, -1 do
        local link = hf1.histfig_links[i]

        if link._type == link_type
            and link.target_hf == unit2.hist_figure_id
        then
            hf1.histfig_links:erase(i)
            link:delete()
            print(
                'Removed historical figure link: ' ..
                tostring(unit1.hist_figure_id) ..
                ' -> ' ..
                tostring(unit2.hist_figure_id)
            )
            return true
        end
    end

    return false
end

local function add_hf_link(unit1, unit2, link_type, strength)
    if not unit1 or not unit2 or not link_type then return nil end

    local existing = get_hf_link(unit1, unit2, link_type)
    if existing then
        return existing
    end

    local hf1 = get_hf(unit1)
    if not hf1 then
        print('Could not find historical figure for link source.')
        return nil
    end

    local ok, link = pcall(function()
        return link_type:new()
    end)

    if not ok or not link then
        print('Could not create historical figure link.')
        return nil
    end

    link.target_hf = unit2.hist_figure_id
    link.link_strength = clamp_relationship_strength(strength or 0)

    hf1.histfig_links:insert('#', link)

    print(
        'Added historical figure link: ' ..
        tostring(unit1.hist_figure_id) ..
        ' -> ' ..
        tostring(unit2.hist_figure_id) ..
        ' strength=' ..
        tostring(link.link_strength)
    )

    return link
end

local function get_spouse_link(unit1, unit2)
    return get_hf_link(unit1, unit2, df.histfig_hf_link_spousest)
end

local function get_lover_link(unit1, unit2)
    return get_hf_link(unit1, unit2, df.histfig_hf_link_loverst)
end

local function get_romantic_link(unit1, unit2)
    if not unit1 or not unit2 then return nil end

    local spouse_link = get_spouse_link(unit1, unit2)
    if spouse_link then
        return spouse_link
    end

    local lover_link = get_lover_link(unit1, unit2)
    if lover_link then
        return lover_link
    end

    return nil
end

local function has_spouse_relationship(unit1, unit2)
    return get_spouse_link(unit1, unit2) ~= nil
        or get_spouse_link(unit2, unit1) ~= nil
end

local function has_lover_relationship(unit1, unit2)
    return get_lover_link(unit1, unit2) ~= nil
        or get_lover_link(unit2, unit1) ~= nil
end

local function ensure_lover_relationship(unit1, unit2)
    if not unit1 or not unit2 then return false end

    local link1 = get_lover_link(unit1, unit2)
    local link2 = get_lover_link(unit2, unit1)

    if not link1 then
        link1 = add_hf_link(unit1, unit2, df.histfig_hf_link_loverst, 0)
    end

    if not link2 then
        link2 = add_hf_link(unit2, unit1, df.histfig_hf_link_loverst, 0)
    end

    return link1 ~= nil and link2 ~= nil
end

local function get_relationship_type(unit1, unit2)
    if has_spouse_relationship(unit1, unit2) then
        return 'Spouse'
    end

    if has_lover_relationship(unit1, unit2) then
        return 'Lover'
    end

    return 'None'
end

local function get_relationship_strength(unit1, unit2)
    local romantic_link = get_romantic_link(unit1, unit2)

    if romantic_link then
        return romantic_link.link_strength or 0
    end

    romantic_link = get_romantic_link(unit2, unit1)

    if romantic_link then
        return romantic_link.link_strength or 0
    end

    return 0
end

local function adjust_existing_link_strength(link, amount, label)
    if not link then return false end

    local before = link.link_strength or 0
    link.link_strength = clamp_relationship_strength(before + amount)

    print(
        tostring(label or 'Relationship link') .. ': ' ..
        tostring(before) ..
        ' -> ' ..
        tostring(link.link_strength)
    )

    return true
end

local function adjust_relationship_strength(unit1, unit2, amount)
    if not unit1 or not unit2 then return false end

    local adjusted = false

    if has_spouse_relationship(unit1, unit2) then
        adjusted = adjust_existing_link_strength(
            get_spouse_link(unit1, unit2),
            amount,
            'Spouse link 1'
        ) or adjusted

        adjusted = adjust_existing_link_strength(
            get_spouse_link(unit2, unit1),
            amount,
            'Spouse link 2'
        ) or adjusted

        return adjusted
    end

    if has_lover_relationship(unit1, unit2) then
        adjusted = adjust_existing_link_strength(
            get_lover_link(unit1, unit2),
            amount,
            'Lover link 1'
        ) or adjusted

        adjusted = adjust_existing_link_strength(
            get_lover_link(unit2, unit1),
            amount,
            'Lover link 2'
        ) or adjusted

        return adjusted
    end

    return false
end

local function complete_romance_quest_relationship(unit1, unit2, reward)
    if not unit1 or not unit2 then
        return false, 'No valid units selected.'
    end

    if has_spouse_relationship(unit1, unit2) then
        local adjusted = adjust_relationship_strength(unit1, unit2, reward)
        return adjusted, adjusted and 'Spouse relationship strengthened.' or 'Could not strengthen spouse relationship.'
    end

    if has_lover_relationship(unit1, unit2) then
        local adjusted = adjust_relationship_strength(unit1, unit2, reward)
        return adjusted, adjusted and 'Lover relationship strengthened.' or 'Could not strengthen lover relationship.'
    end

    local compatible, message = can_start_lover_relationship(unit1, unit2)

    if not compatible then
        return false, message
    end

    ensure_lover_relationship(unit1, unit2)

    local adjusted = adjust_relationship_strength(unit1, unit2, reward)
    return adjusted, adjusted and 'Lover relationship created and strengthened.' or 'Could not create lover relationship.'
end


local function break_up_relationship(unit1, unit2)
    if not unit1 or not unit2 then return false end

    local changed = false

    changed = remove_hf_link(unit1, unit2, df.histfig_hf_link_loverst) or changed
    changed = remove_hf_link(unit2, unit1, df.histfig_hf_link_loverst) or changed

    changed = remove_hf_link(unit1, unit2, df.histfig_hf_link_spousest) or changed
    changed = remove_hf_link(unit2, unit1, df.histfig_hf_link_spousest) or changed

    if unit1.relationship_ids and unit1.relationship_ids.Spouse == unit2.id then
        unit1.relationship_ids.Spouse = -1
        changed = true
    end

    if unit2.relationship_ids and unit2.relationship_ids.Spouse == unit1.id then
        unit2.relationship_ids.Spouse = -1
        changed = true
    end

    return changed
end


local function get_marriage_chance(unit1, unit2)
    local link = get_lover_link(unit1, unit2) or get_lover_link(unit2, unit1)

    if not link then
        return 0
    end

    return clamp_relationship_strength(link.link_strength or 0)
end

local function remove_lover_relationship(unit1, unit2)
    if not unit1 or not unit2 then return false end

    local changed = false
    changed = remove_hf_link(unit1, unit2, df.histfig_hf_link_loverst) or changed
    changed = remove_hf_link(unit2, unit1, df.histfig_hf_link_loverst) or changed

    return changed
end

local function set_spouse_relationship(unit1, unit2, strength)
    if not unit1 or not unit2 then return false end

    local spouse_strength = clamp_relationship_strength(strength or 0)

    -- Lover links are replaced by spouse links.
    remove_lover_relationship(unit1, unit2)

    local link1 = add_hf_link(unit1, unit2, df.histfig_hf_link_spousest, spouse_strength)
    local link2 = add_hf_link(unit2, unit1, df.histfig_hf_link_spousest, spouse_strength)

    if unit1.relationship_ids then
        unit1.relationship_ids.Spouse = unit2.id
    end

    if unit2.relationship_ids then
        unit2.relationship_ids.Spouse = unit1.id
    end

    return link1 ~= nil and link2 ~= nil
end

local function weaken_lover_relationship(unit1, unit2, amount)
    if not unit1 or not unit2 then return false, 0 end

    local link1 = get_lover_link(unit1, unit2)
    local link2 = get_lover_link(unit2, unit1)

    if not link1 and not link2 then
        return false, 0
    end

    local before = get_marriage_chance(unit1, unit2)
    local after = before - math.abs(tonumber(amount) or 0)

    if after <= 0 then
        remove_lover_relationship(unit1, unit2)
        return true, 0
    end

    after = clamp_relationship_strength(after)

    if link1 then
        link1.link_strength = after
    end

    if link2 then
        link2.link_strength = after
    end

    print('Lover relationship weakened: ' .. tostring(before) .. ' -> ' .. tostring(after))

    return true, after
end

local function try_get_married(unit1, unit2)
    if not unit1 or not unit2 then
        return false, 'No valid units selected.'
    end

    if has_spouse_relationship(unit1, unit2) then
        return false, 'They are already spouses.'
    end

    if not has_lover_relationship(unit1, unit2) then
        return false, 'They need to be lovers first.'
    end

    -- Marriage requires both units to have marriage-level interest.
    -- 0 = uninterested, 1 = romance, 2 = marry
    local interest1 = get_orientation_interest(unit1, unit2)
    local interest2 = get_orientation_interest(unit2, unit1)

    if interest1 < 2 then
        return false, 'The adventurer is open to romance, but not marriage with this NPC\'s sex.'
    end

    if interest2 < 2 then
        return false, 'The NPC is open to romance, but not marriage with the adventurer\'s sex.'
    end

    local chance = get_marriage_chance(unit1, unit2)
    local roll = math.random(100)

    print('Marriage proposal roll: ' .. tostring(roll) .. ' / chance=' .. tostring(chance))

    if roll <= chance then
        local married = set_spouse_relationship(unit1, unit2, chance)

        if married then
            return true, 'Marriage accepted. They are now spouses.'
        end

        return false, 'Marriage succeeded, but spouse links could not be created.'
    end

    local changed, new_strength = weaken_lover_relationship(unit1, unit2, CANCEL_PENALTY)

    if changed and new_strength <= 0 then
        return false, 'Marriage rejected. Lover relationship ended.'
    elseif changed then
        return false, 'Marriage rejected. Lover strength decreased to ' .. tostring(new_strength) .. '.'
    end

    return false, 'Marriage rejected.'
end

local function get_biological_pair(unit1, unit2)
    if not unit1 or not unit2 then
        return nil, nil
    end

    if dfhack.units.isMale(unit1) and dfhack.units.isFemale(unit2) then
        return unit1, unit2
    elseif dfhack.units.isFemale(unit1) and dfhack.units.isMale(unit2) then
        return unit2, unit1
    end

    return nil, nil
end

local function try_set_pregnancy(unit1, unit2, gestation_timer)
    if not unit1 or not unit2 then
        return false, 'No valid units selected.'
    end

    if dfhack.units.isAnimal(unit1) or dfhack.units.isAnimal(unit2) then
        return false, 'Pregnancy is only supported for sentient units.'
    end

    if not dfhack.units.isAdult(unit1) or not dfhack.units.isAdult(unit2) then
        return false, 'Both units must be adults.'
    end

    local male, female = get_biological_pair(unit1, unit2)

    if not male or not female then
        return false, 'No pregnancy possible.'
    end

    local current_timer = tonumber(female.pregnancy_timer) or 0

	if current_timer > 0 then
		return false, get_unit_name(female) .. ' is already pregnant.'
	end

    local timer = 1

    local ok, message = setpregnancy.set_pregnancy_for_pair(
        unit1,
        unit2,
        timer
    )

    print('Pregnancy result: ' .. tostring(ok) .. ' - ' .. tostring(message))

    return ok, message
end

local function try_spend_the_night(unit1, unit2)
    if not unit1 or not unit2 then
        return false, 'No valid units selected.'
    end

    if not has_lover_relationship(unit1, unit2)
        and not has_spouse_relationship(unit1, unit2)
    then
        return false, 'They need to be lovers or spouses first.'
    end

    local compatible, message = can_start_lover_relationship(unit1, unit2)

    if not compatible then
        return false, message
    end

    local chance = get_relationship_strength(unit1, unit2)
    local roll = math.random(100)

    print('Spend the night roll: ' .. tostring(roll) .. ' / chance=' .. tostring(chance))

    if roll > chance then
        if has_lover_relationship(unit1, unit2) then
            weaken_lover_relationship(unit1, unit2, SPEND_NIGHT_REJECTION_PENALTY)
        else
            adjust_relationship_strength(unit1, unit2, -SPEND_NIGHT_REJECTION_PENALTY)
        end

        return false, 'They declined. Relationship strength decreased by 1.'
    end

    adjust_relationship_strength(unit1, unit2, SPEND_NIGHT_REWARD)

    local pregnancy_roll = math.random(100)
    print('Pregnancy roll: ' .. tostring(pregnancy_roll) .. ' / chance=' .. tostring(SPEND_NIGHT_PREGNANCY_CHANCE))

    if pregnancy_roll <= SPEND_NIGHT_PREGNANCY_CHANCE then
        local pregnant, pregnancy_message = try_set_pregnancy(
            unit1,
            unit2,
            STANDARD_GESTATION_TICKS
        )

        if pregnant then
            return true, 'They spent the night together. ' .. pregnancy_message
        end
    end

    return true, 'They spent the night together.'
end

-------------------------------------------------
-- Inventory Helpers
-------------------------------------------------

local function item_matches_quest(item, quest)
    if not item or not quest then
        return false
    end

    if tonumber(item:getType()) ~= tonumber(quest.item_type) then
        return false
    end

    -- Allow any weapon to satisfy weapon quests
    if tonumber(quest.item_type) == tonumber(df.item_type.WEAPON) then
        return true
    end

    local subtype = -1

    if item.getSubtype then
        subtype = item:getSubtype()
    elseif item.subtype then
        subtype = item.subtype
    end

    if tonumber(quest.item_subtype or -1) ~= -1 then
        return tonumber(subtype or -1) == tonumber(quest.item_subtype)
    end

    return true
end

local function get_item_display_name(item)
    if not item then return 'Unknown item' end

    local ok, name = pcall(function()
        return dfhack.items.getDescription(item, 0, true)
    end)

    if ok and name and name ~= '' then
        return name
    end

    return 'Item #' .. tostring(item.id)
end

local function get_matching_inventory_items(unit, quest)
    local matches = {}

    if not unit or not quest then
        return matches
    end

    for _, inv_item in ipairs(unit.inventory) do
        local item = inv_item.item

        if item and item_matches_quest(item, quest) then
            table.insert(matches, {
                item = item,
                inv_item = inv_item,
                text = get_item_display_name(item),
            })
        end
    end

    return matches
end

-------------------------------------------------
-- Reaction / Gift Helpers
-------------------------------------------------

local function is_adventure_reaction(reaction)
    return reaction
        and reaction.flags
        and reaction.flags.ADVENTURE_MODE_ENABLED
        and reaction.products
        and #reaction.products > 0
end

local function get_item_type_name(item_type, item_subtype)
    if item_type == df.item_type.TOOL and item_subtype and item_subtype ~= -1 then
        local def = df.global.world.raws.itemdefs.tools[item_subtype]
        if def and def.name then return def.name end
    elseif item_type == df.item_type.TOY and item_subtype and item_subtype ~= -1 then
        local def = df.global.world.raws.itemdefs.toys[item_subtype]
        if def and def.name then return def.name end
    elseif item_type == df.item_type.INSTRUMENT and item_subtype and item_subtype ~= -1 then
        local def = df.global.world.raws.itemdefs.instruments[item_subtype]
        if def and def.name then return def.name end
    end

    local attrs = item_type and df.item_type.attrs[item_type]

    if attrs and attrs.caption then
        return attrs.caption
    end

    return tostring(item_type)
end

local function get_reaction_product_gift(product)
    if product._type ~= df.reaction_product_itemst then
        return nil
    end

    local item_name = get_item_type_name(product.item_type, product.item_subtype)

    if not item_name then return nil end

    return {
        item_type = tonumber(product.item_type) or -1,
        item_subtype = tonumber(product.item_subtype) or -1,
        item_name = safe_text(item_name),
    }
end

local function get_adventure_reaction_gifts()
    local gifts = {}
    local reactions = df.global.world.raws.reactions.reactions

    for _, reaction in ipairs(reactions) do
        if is_adventure_reaction(reaction) then
            for _, product in ipairs(reaction.products) do
                local gift = get_reaction_product_gift(product)

                if gift then
                    gift.reaction_code = safe_text(reaction.code)
                    gift.reaction_name = safe_text(reaction.name)

                    table.insert(gifts, gift)
                end
            end
        end
    end

    return gifts
end

local function get_random_gift_item()
    local gifts = get_adventure_reaction_gifts()

    if #gifts == 0 then
        return nil
    end

    return gifts[math.random(#gifts)]
end

local function get_gift_display_name(gift)
    return safe_text(gift.item_name or 'unknown item')
end

-------------------------------------------------
-- Gift Item Selection Window
-------------------------------------------------

GiftItemSelectionWindow = defclass(GiftItemSelectionWindow, widgets.Window)
GiftItemSelectionWindow.ATTRS {
    frame_title='Select Gift Item',
    frame={w=72, h=18, r=2, t=18},
    frame_inset={t=1, l=1, r=1},
    resizable=true,

    adventurer=DEFAULT_NIL,
    target=DEFAULT_NIL,
    quest=DEFAULT_NIL,
    quest_key=DEFAULT_NIL,
    parent_screen=DEFAULT_NIL,
}

function GiftItemSelectionWindow:init()
    self.status_message = ''
    self.items = get_matching_inventory_items(self.adventurer, self.quest)

    local choices = {}

    for _, entry in ipairs(self.items) do
        table.insert(choices, {
            text=entry.text,
            data=entry,
        })
    end

    self:addviews{
        widgets.Label{
            frame={t=0, l=0},
            text='Choose which item to give:',
            text_pen=COLOR_WHITE,
        },

        widgets.List{
            view_id='item_list',
            frame={t=2, l=0, r=0, b=3},
            choices=choices,
            on_submit=function(_, choice)
                if choice and choice.data then
                    self:give_item(choice.data.item)
                end
            end,
        },

        widgets.HotkeyLabel{
            frame={b=1, l=0},
            label='Cancel',
            key='LEAVESCREEN',
            auto_width=true,
            on_activate=function()
                if self.parent_screen then
                    self.parent_screen:dismiss()
                else
                    self:dismiss()
                end
            end,
        },

        widgets.Label{
            frame={b=0, l=0},
            text={{text=function()
                return self.status_message
            end}},
            text_pen=COLOR_LIGHTRED,
        },
    }
end

function GiftItemSelectionWindow:give_item(item)
    if not item then
        self.status_message = 'No item selected.'
        return
    end

    if not has_spouse_relationship(self.adventurer, self.target)
        and not has_lover_relationship(self.adventurer, self.target)
    then
        local compatible, message = can_start_lover_relationship(self.adventurer, self.target)

        if not compatible then
            self.status_message = message
            return
        end
    end

    local moved = dfhack.items.moveToInventory(
        item,
        self.target,
        df.inv_item_role_type.Hauled,
        -1
    )

    if not moved then
        self.status_message = 'Could not move item to NPC inventory.'
        return
    end

    local adjusted, relationship_message = complete_romance_quest_relationship(
        self.adventurer,
        self.target,
        COMPLETE_REWARD
    )

    print('Romance relationship adjusted: ' .. tostring(adjusted))
    print('New relationship type: ' ..
        tostring(get_relationship_type(self.adventurer, self.target)))
    print('New relationship strength: ' ..
        tostring(get_relationship_strength(self.adventurer, self.target)))

    remove_quest(self.quest_key)
    save_quests()

    if self.parent_screen then
        self.parent_screen:dismiss()
    else
        self:dismiss()
    end
end
GiftItemSelectionScreen = defclass(GiftItemSelectionScreen, gui.ZScreen)
GiftItemSelectionScreen.ATTRS {
    focus_path='romance-quest-gift-select',

    adventurer=DEFAULT_NIL,
    target=DEFAULT_NIL,
    quest=DEFAULT_NIL,
    quest_key=DEFAULT_NIL,
}

function GiftItemSelectionScreen:init()
    self:addviews{
        GiftItemSelectionWindow{
            adventurer=self.adventurer,
            target=self.target,
            quest=self.quest,
            quest_key=self.quest_key,
            parent_screen=self,
        }
    }
end

-------------------------------------------------
-- RomanceQuestWindow
-------------------------------------------------

RomanceQuestWindow = defclass(RomanceQuestWindow, widgets.Window)
RomanceQuestWindow.ATTRS {
    frame_title='Romance',
    frame={w=70, h=24, r=2, t=18},
    frame_inset={t=1, l=1, r=1},
    resizable=true,
}

function RomanceQuestWindow:init()
    self.adventurer = get_adventurer()
    self.target = get_selected_unit()
    self.quest_key = get_quest_key(self.adventurer, self.target)
    self.status_message = ''
    self.selecting_item = false
    self.item_choices = {}
    self.dirty = 0

    print('Adventurer: ' .. get_safe_unit_name(self.adventurer))
    print('Target: ' .. get_safe_unit_name(self.target))
    print('Quest key: ' .. tostring(self.quest_key))
    print('Loaded quest: ' .. tostring(get_quest(self.quest_key) ~= nil))

    self:addviews{
        widgets.Label{
            frame={t=0, l=0},
            text={{text=function()
                return 'NPC: ' .. get_unit_name(self.target)
            end}},
            text_pen=COLOR_LIGHTMAGENTA,
        },

        widgets.Label{
            frame={t=2, l=0},
            text={{text=function()
                return 'Relationship: ' ..
                    get_relationship_type(self.adventurer, self.target)
            end}},
            text_pen=COLOR_CYAN,
        },

        widgets.Label{
            frame={t=3, l=0},
            text={{text=function()
                return 'Relationship Strength: ' ..
                    tostring(get_relationship_strength(self.adventurer, self.target))
            end}},
            text_pen=COLOR_GREEN,
        },

        widgets.HotkeyLabel{
            frame={t=5, l=0},
            label='Give Gift',
            key='CUSTOM_G',
            auto_width=true,
            on_activate=function()
                self:create_gift_quest()
            end,
            visible=function()
                return not self.selecting_item
            end,
            enabled=function()
                return self.adventurer ~= nil
                    and self.target ~= nil
                    and self.quest_key ~= nil
                    and not self:has_active_quest()
            end,
        },

        widgets.HotkeyLabel{
            frame={t=6, l=0},
            label='Complete Quest',
            key='CUSTOM_Q',
            auto_width=true,
            on_activate=function()
                self:complete_quest()
            end,
            visible=function()
                return not self.selecting_item
            end,
            enabled=function()
                return self:has_active_quest()
            end,
        },

        widgets.HotkeyLabel{
            frame={t=7, l=0},
            label='Cancel Current Gift Quest',
            key='CUSTOM_C',
            auto_width=true,
            on_activate=function()
                self:cancel_gift_quest()
            end,
            visible=function()
                return not self.selecting_item
            end,
            enabled=function()
                return self:has_active_quest()
            end,
        },

        widgets.HotkeyLabel{
            frame={t=8, l=0},
            label='Break Up',
            key='CUSTOM_B',
            auto_width=true,
            on_activate=function()
                local changed = break_up_relationship(self.adventurer, self.target)

                if changed then
                    self.status_message = 'Relationship reset.'
                else
                    self.status_message = 'No romantic relationship to reset.'
                end

                self.dirty = 2
            end,
            visible=function()
                return not self.selecting_item
            end,
            enabled=function()
                return self.adventurer ~= nil
                    and self.target ~= nil
                    and get_romantic_link(self.adventurer, self.target) ~= nil
            end,
        },

        widgets.HotkeyLabel{
            frame={t=9, l=0},
            label='Get Married',
            key='CUSTOM_M',
            auto_width=true,
            on_activate=function()
                local success, message = try_get_married(self.adventurer, self.target)
                self.status_message = message

                if success then
                    print('Marriage success: ' .. tostring(message))
                else
                    print('Marriage result: ' .. tostring(message))
                end

                self.dirty = 2
            end,
            visible=function()
                return not self.selecting_item
            end,
            enabled=function()
                return self.adventurer ~= nil
                    and self.target ~= nil
                    and has_lover_relationship(self.adventurer, self.target)
                    and not has_spouse_relationship(self.adventurer, self.target)
            end,
        },

        widgets.HotkeyLabel{
            frame={t=10, l=0},
            label='Spend the Night',
            key='CUSTOM_N',
            auto_width=true,
            on_activate=function()
                local success, message = try_spend_the_night(self.adventurer, self.target)
                self.status_message = message

                if success then
                    print('Spend the night success: ' .. tostring(message))
                else
                    print('Spend the night result: ' .. tostring(message))
                end

                self.dirty = 2
            end,
            visible=function()
                return not self.selecting_item
            end,
            enabled=function()
                return self.adventurer ~= nil
                    and self.target ~= nil
                    and (has_lover_relationship(self.adventurer, self.target)
                        or has_spouse_relationship(self.adventurer, self.target))
            end,
        },

        widgets.Label{
            frame={t=12, l=0},
            text='Select an item to give:',
            text_pen=COLOR_WHITE,
            visible=function()
                return self.selecting_item
            end,
        },

        widgets.List{
            view_id='item_list',
            frame={t=13, l=0, r=0, b=3},
            choices={},
            visible=function()
                return self.selecting_item
            end,
            on_submit=function(_, choice)
                self:give_selected_item(choice)
            end,
        },

        widgets.HotkeyLabel{
            frame={b=2, l=0},
            label='Cancel Item Selection',
            key='LEAVESCREEN',
            auto_width=true,
            on_activate=function()
                self:cancel_item_selection()
            end,
            visible=function()
                return self.selecting_item
            end,
        },

        widgets.Label{
            frame={t=13, l=0},
            text={{text=function()
                return self:get_quest_text()
            end}},
            text_pen=COLOR_YELLOW,
            visible=function()
                return not self.selecting_item
            end,
        },

        widgets.Label{
            frame={b=0, l=0},
            text={{text=function()
                return self.status_message
            end}},
            text_pen=COLOR_LIGHTRED,
        },
    }
end

function RomanceQuestWindow:render(dc)
    if self.dirty > 0 then
        self:updateLayout()
        self.dirty = self.dirty - 1
    end

    RomanceQuestWindow.super.render(self, dc)
end

function RomanceQuestWindow:has_active_quest()
    return self.quest_key and get_quest(self.quest_key) ~= nil
end

function RomanceQuestWindow:get_active_quest()
    if not self.quest_key then
        return nil
    end

    return get_quest(self.quest_key)
end

function RomanceQuestWindow:create_gift_quest()
    print('CREATE_GIFT_QUEST CALLED')

    if not self.adventurer then
        self.status_message = 'No adventurer found.'
        return
    end

    if not self.target then
        self.status_message = 'No NPC selected.'
        return
    end

    if not self.quest_key then
        self.status_message = 'Could not create quest key.'
        return
    end

    if self:has_active_quest() then
        self.status_message = 'Finish or cancel the current gift quest first.'
        return
    end

    if not has_spouse_relationship(self.adventurer, self.target)
        and not has_lover_relationship(self.adventurer, self.target)
    then
        local compatible, message = can_start_lover_relationship(self.adventurer, self.target)

        if not compatible then
            self.status_message = message
            return
        end
    end

    local gift = get_random_gift_item()

    if not gift then
        local ok = set_quest(self.quest_key, {
            type='error',
            target_id=self.target.id,
            target_hfid=self.target.hist_figure_id,
            message='No Adventure Mode craftable reaction products found.',
            completed=false,
        })

        if ok then
            save_quests()
            self.status_message = 'Error quest saved.'
        else
            self.status_message = 'Failed to save error quest.'
        end

        return
    end

    local ok = set_quest(self.quest_key, {
        type='gift',

        target_id=self.target.id,
        target_hfid=self.target.hist_figure_id,

        item_type=gift.item_type,
        item_subtype=gift.item_subtype,
        item_name=gift.item_name,

        display_name=get_gift_display_name(gift),

        reaction_code=gift.reaction_code,
        reaction_name=gift.reaction_name,

        completed=false,
    })

    if ok then
        save_quests()
        self.status_message = 'Gift quest created and saved.'
    else
        self.status_message = 'Failed to create gift quest.'
    end
end

function RomanceQuestWindow:complete_quest()
    local quest = self:get_active_quest()

    if not quest then
        self.status_message = 'There is no active quest to complete.'
        return
    end

    if quest.type ~= 'gift' then
        self.status_message = 'This quest cannot be completed.'
        return
    end

    local matching_items = get_matching_inventory_items(self.adventurer, quest)

    if #matching_items <= 0 then
        self.status_message =
            'You do not have the required item: ' ..
            tostring(quest.display_name or 'gift') ..
            '.'
        self.dirty = 2
        return
    end

    self:show_item_selection(matching_items)
end

function RomanceQuestWindow:show_item_selection(matching_items)
    self.selecting_item = true
    self.item_choices = {}

    for _, entry in ipairs(matching_items) do
        table.insert(self.item_choices, {
            text=entry.text,
            data=entry,
        })
    end

    self.subviews.item_list:setChoices(self.item_choices)
    self.status_message = 'Select the item to give, then press Enter.'
    self.dirty = 2
end

function RomanceQuestWindow:cancel_item_selection()
    self.selecting_item = false
    self.item_choices = {}
    self.subviews.item_list:setChoices(self.item_choices)
    self.status_message = 'Gift selection cancelled.'
    self.dirty = 2
end

function RomanceQuestWindow:give_selected_item(choice)
    if not choice or not choice.data or not choice.data.item then
        self.status_message = 'No item selected.'
        self.dirty = 2
        return
    end

    local item = choice.data.item
    local quest = self:get_active_quest()

    if not quest then
        self.status_message = 'There is no active quest to complete.'
        self.selecting_item = false
        self.dirty = 2
        return
    end

    if not has_spouse_relationship(self.adventurer, self.target)
        and not has_lover_relationship(self.adventurer, self.target)
    then
        local compatible, message = can_start_lover_relationship(self.adventurer, self.target)

        if not compatible then
            self.status_message = message
            self.selecting_item = false
            self.item_choices = {}
            self.subviews.item_list:setChoices(self.item_choices)
            self.dirty = 2
            return
        end
    end

    local moved = dfhack.items.moveToInventory(
        item,
        self.target,
        df.inv_item_role_type.Hauled,
        -1
    )

    if not moved then
        self.status_message = 'Could not move item to NPC inventory.'
        self.dirty = 2
        return
    end

    local before_strength = get_relationship_strength(self.adventurer, self.target)

    local adjusted, relationship_message = complete_romance_quest_relationship(
        self.adventurer,
        self.target,
        COMPLETE_REWARD
    )

    local after_strength = get_relationship_strength(self.adventurer, self.target)

    print('Romance relationship adjusted: ' .. tostring(adjusted))
    print('Relationship type after quest: ' ..
        tostring(get_relationship_type(self.adventurer, self.target)))
    print('Relationship strength after quest: ' ..
        tostring(before_strength) ..
        ' -> ' ..
        tostring(after_strength))

    remove_quest(self.quest_key)
    save_quests()

    self.selecting_item = false
    self.item_choices = {}
    self.subviews.item_list:setChoices(self.item_choices)

    if adjusted then
        self.status_message =
            'Gift delivered. Relationship strength increased to ' ..
            tostring(after_strength) ..
            '.'
    else
        self.status_message = relationship_message or 'Gift delivered, but relationship was not adjusted.'
    end

    self.dirty = 2
	
end

function RomanceQuestWindow:cancel_gift_quest()
    if not self:has_active_quest() then
        self.status_message = 'There is no active gift quest to cancel.'
        return
    end

    remove_quest(self.quest_key)

    local adjusted = adjust_relationship_strength(
        self.adventurer,
        self.target,
        -CANCEL_PENALTY
    )

    save_quests()

    if adjusted then
        self.status_message = 'Gift quest cancelled. Relationship strength decreased.'
    else
        self.status_message = 'Gift quest cancelled.'
    end
end

function RomanceQuestWindow:get_quest_text()
    if not self.adventurer then
        return 'No adventurer found.'
    end

    if not self.target then
        return 'No NPC selected.'
    end

    if not self.quest_key then
        return 'Could not create quest key.'
    end

    local quest = self:get_active_quest()

    if not quest then
        return 'No active romance quest.'
    end

    if quest.type == 'error' then
        return tostring(quest.message or 'Unknown quest error.')
    end

    return 'Quest: Bring a ' ..
        tostring(quest.display_name or 'gift') ..
        ' to ' ..
        get_unit_name(self.target) ..
        '.'
end

-------------------------------------------------
-- RomanceQuestScreen
-------------------------------------------------

RomanceQuestScreen = defclass(RomanceQuestScreen, gui.ZScreen)
RomanceQuestScreen.ATTRS {
    focus_path='romance-quests',
}

function RomanceQuestScreen:init()
    self:addviews{
        RomanceQuestWindow{}
    }
end

function RomanceQuestScreen:onDismiss()
    save_quests()
    view = nil
end

-------------------------------------------------
-- Screen Refresh Helper
-------------------------------------------------

function reopen_romance_screen()
    if view then
        pcall(function()
            view:dismiss()
        end)

        view = nil
    end

    view = RomanceQuestScreen{}:show()
end

-------------------------------------------------
-- Script Entry
-------------------------------------------------

if not dfhack.isMapLoaded() then
    qerror('Requires a loaded map')
end

math.randomseed(os.time())

load_quests()

print('Romance quest persistent key: ' .. PERSIST_KEY)
print('Loaded romance quest count: ' .. tostring(#ACTIVE_QUESTS))

reopen_romance_screen()
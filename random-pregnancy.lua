-- random-pregnancy.lua
-- Impregnates a random valid female with a random valid male
-- Supports configurable pregnancy_timer (default: ~9 months)

local rng = dfhack.random.new()

--========================
--	Args
--========================
local args = {...}

local function has_flag(flag)
	for _,a in ipairs(args) do
		if a == flag then
			return true
		end
	end
	return false
end

local function get_arg_value(flag)
	for i=1,#args do
		if args[i] == flag then
			return args[i+1]
		end
	end
	return nil
end

local SILENT = has_flag('--silent')
local GLOBAL = has_flag('--global')
local INSTANT = has_flag('--instant')

local radius_val = tonumber(get_arg_value('--radius') or '')
local RADIUS = radius_val or 50

-- Time constants (based on 1 day ~= 2400 ticks; DF month = 28 days)
local TICKS_PER_DAY = 2400
local TICKS_PER_MONTH = 28 * TICKS_PER_DAY			-- 67200
local DEFAULT_TIMER = 9 * TICKS_PER_MONTH			-- 604800 (~9 months)

local timer_arg = tonumber(get_arg_value('--timer') or '')
local PREG_TIMER = DEFAULT_TIMER
if INSTANT then
	PREG_TIMER = 1
elseif timer_arg and timer_arg > 0 then
	PREG_TIMER = math.floor(timer_arg)
end

local function fail(msg)
	if SILENT then
		return false
	end
	qerror(msg)
end

--========================
--	Helpers
--========================
local function get_adv()
	return dfhack.world.getAdventurer()
end

-- sentience check from raws
local function is_sentient(u)
	local creature = df.creature_raw.find(u.race)
	if not creature then return false end
	local caste = creature.caste[u.caste]
	return caste.flags.CAN_LEARN and caste.flags.CAN_SPEAK
end

local function is_valid_female(u)
	return dfhack.units.isAlive(u)
		and not dfhack.units.isChild(u)
		and not dfhack.units.isBaby(u)
		and is_sentient(u)
		and u.sex == 0
		and (u.pregnancy_timer or 0) == 0
end

local function is_valid_male(u)
	return dfhack.units.isAlive(u)
		and not dfhack.units.isChild(u)
		and not dfhack.units.isBaby(u)
		and is_sentient(u)
		and u.sex == 1
		and u.hist_figure_id ~= -1
end

local function in_radius(u, center, r)
	if not u.pos or not center then return false end
	local dx = u.pos.x - center.x
	local dy = u.pos.y - center.y
	-- Keep it same-z to avoid picking units on other levels
	return (math.abs(dx) <= r and math.abs(dy) <= r and u.pos.z == center.z)
end

--========================
--	Collect candidates
--========================
local center_pos = nil
if not GLOBAL then
	local adv = get_adv()
	if not adv then
		return fail('No adventurer found (use --global if you want global behavior)')
	end
	center_pos = adv.pos
end

local females, males = {}, {}

for _,u in ipairs(df.global.world.units.active) do
	if GLOBAL or in_radius(u, center_pos, RADIUS) then
		if is_valid_female(u) then
			table.insert(females, u)
		elseif is_valid_male(u) then
			table.insert(males, u)
		end
	end
end

if #females == 0 then return fail('No valid female found') end
if #males == 0 then return fail('No valid male found') end

local mother = females[rng:random(#females)]
local father = males[rng:random(#males)]

--========================
--	Set pregnancy
--========================
mother.pregnancy_timer = PREG_TIMER
mother.pregnancy_caste = father.caste
mother.pregnancy_spouse = father.hist_figure_id
mother.pregnancy_genes = df.unit_genes:new()
mother.pregnancy_genes:assign(father.appearance.genes)

if not SILENT then
	print(string.format(
		"Pregnancy set (timer=%d): mother=%s (id=%d), father=%s (hf=%d)",
		PREG_TIMER,
		dfhack.units.getReadableName(mother), mother.id,
		dfhack.units.getReadableName(father), father.hist_figure_id
	))
end

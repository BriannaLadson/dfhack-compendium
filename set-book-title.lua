-- hack/scripts/set-book-title.lua
-- Positional:
--   set-book-title list
--   set-book-title all
--   set-book-title rename              (opens gui/rename for the artifact)
-- Flags:
--   set-book-title -list
--   set-book-title -all
--   set-book-title -title "X"          (written_content title)
--   set-book-title -old "substr"
--   set-book-title -force
--   set-book-title -rename             (same as positional rename)
--   set-book-title -aname "X"          (set artifact name directly)
--   set-book-title -both "X"           (sets BOTH artifact name + written_content title)

local argv = {...}

local function has(tok)
  for _, v in ipairs(argv) do
    if v == tok then return true end
  end
  return false
end

-- Grabs an option value.
-- Supports:
--   -opt value
--   -opt "multi word value"
--   -opt multi word value (without quotes)  <-- joins until next flag
local function opt_join(tok)
  for i = 1, #argv do
    if argv[i] == tok then
      if i == #argv then return nil end
      local parts = {}
      for j = i + 1, #argv do
        local a = argv[j]
        if type(a) == 'string' and a:sub(1,1) == '-' then break end
        table.insert(parts, a)
      end
      if #parts == 0 then return nil end
      return table.concat(parts, ' ')
    end
  end
  return nil
end

-- accept both positional and flag forms
local list_mode   = has('list') or has('-list')
local all_mode    = has('all')  or has('-all')
local force       = has('force') or has('-force')
local rename_mode = has('rename') or has('-rename') or has('--rename')

local old_match = opt_join('-old')                      -- substring (string) or nil
local new_title = opt_join('-title') or 'Test Title'    -- written_content title
local new_aname = opt_join('-aname')                    -- artifact name (string) or nil
local both_name = opt_join('-both')                     -- both (string) or nil

-- If -both is provided, it overrides -title and -aname
if both_name and #both_name > 0 then
  new_title = both_name
  new_aname = both_name
end

local item = dfhack.gui.getSelectedItem(true)
if not item then
  qerror('Select a book/scroll/quire/codex item first.')
end

-- Find the artifact_record that points at this item
local function find_artifact_for_item(it)
  for _, a in ipairs(df.global.world.artifacts.all) do
    if a.item and a.item.id == it.id then
      return a
    end
  end
  return nil
end

-- Helper to set an artifact language_name to a simple first_name string
-- IMPORTANT: do NOT call :resize() on words/parts_of_speech in your build (they are fixed arrays).
local function set_language_name_to_string(lang_name, s)
  lang_name.has_name = true
  lang_name.first_name = s

  -- Optional cleanup (safe probes; won't error if fields don't exist)
  pcall(function() lang_name.nickname = '' end)
  pcall(function() lang_name.language = 0 end)
  pcall(function() lang_name.translation = 0 end)
end

-- If user asked to rename artifact label (or -both), do that first (then continue if -both wants title too)
local function maybe_rename_artifact()
  if not new_aname then return false end
  local art = find_artifact_for_item(item)
  if not art then
    qerror(('Selected item id %d is not found in world.artifacts.all. Is it definitely an artifact?'):format(item.id))
  end
  set_language_name_to_string(art.name, new_aname)
  print(('Set ARTIFACT name (artifact id=%d) to %q'):format(art.id, new_aname))
  return true
end

-- If user asked to open GUI rename (only), do that and exit
if rename_mode and not both_name and not new_aname then
  local art = find_artifact_for_item(item)
  if not art then
    qerror(('Selected item id %d is not found in world.artifacts.all. Is it definitely an artifact?'):format(item.id))
  end
  dfhack.run_command(('gui/rename -a %d'):format(art.id))
  return
end

-- Collect written_content ids from ANY improvement.contents (works across versions)
local wc_ids, seen = {}, {}
local function add_id(id)
  if id and id >= 0 and not seen[id] then
    seen[id] = true
    table.insert(wc_ids, id)
  end
end

for _, imp in ipairs(item.improvements or {}) do
  local ok, contents = pcall(function() return imp.contents end)
  if ok and contents then
    for _, id in ipairs(contents) do add_id(id) end
  end
end

-- LIST MODE
if list_mode then
  local art = find_artifact_for_item(item)
  print(('Item id=%d type=%s'):format(item.id, tostring(item._type)))
  if art then
    print(('Artifact: yes (artifact id=%d)'):format(art.id))
    local ok, desc = pcall(function() return art:describe() end)
    if ok then print('Artifact describe: '..tostring(desc)) end
    print('Artifact first_name: '..tostring(art.name.first_name))
  else
    print('Artifact: not found in world.artifacts.all')
  end
  print('DFHack getBookTitle(): '..tostring(dfhack.items.getBookTitle(item)))
  print('Linked written_content records:')
  for _, id in ipairs(wc_ids) do
    local wc = df.written_content.find(id)
    if wc then
      print(('  wc %-8d title=%q type=%s pages=%d-%d chap=%d sec=%d')
        :format(id, tostring(wc.title), tostring(wc.type),
                wc.page_start, wc.page_end, wc.chapter_number, wc.section_number))
    end
  end
  return
end

-- If we are renaming artifact (either -aname or -both), do it now
if new_aname then
  maybe_rename_artifact()
  -- If user only wanted artifact rename (no -title and no -both), we can stop here.
  if not both_name and not opt_join('-title') then
    return
  end
end

if #wc_ids == 0 then
  qerror('Could not find any written_content ids linked to this item.')
end

-- RENAME written content title(s)
local changed, changed_ids = 0, {}
for _, id in ipairs(wc_ids) do
  local wc = df.written_content.find(id)
  if wc then
    local cur = tostring(wc.title or '')

    local should =
      force or
      all_mode or
      (type(old_match) == 'string' and cur:find(old_match, 1, true) ~= nil) or
      ((not old_match) and (not all_mode) and cur ~= new_title)

    if should then
      wc.title = new_title
      changed = changed + 1
      table.insert(changed_ids, id)
    end
  end
end

print(('Set written_content title to %q on %d record(s).'):format(new_title, changed))
if changed > 0 then
  print('Changed wc ids: '..table.concat(changed_ids, ', '))
end
print('DFHack getBookTitle(): '..tostring(dfhack.items.getBookTitle(item)))

print('Tip: rename artifact label only: set-book-title -aname "Name"')
print('Tip: rename both at once:      set-book-title -both "Name"')
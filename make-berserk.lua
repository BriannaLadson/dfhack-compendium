-- Select Unit
local unit = dfhack.gui.getSelectedUnit()

-- If Valid Unit Is Selected, Make Berserk
if unit then
	-- Set Mood to Berserk
	unit.mood = df.mood_type.Berserk
	print("Unit is now berserk!")
else
	qerror("No unit is selected.")
end
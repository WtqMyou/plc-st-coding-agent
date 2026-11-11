FUNCTION_BLOCK FB
VAR_INPUT
    recipe : ARRAY[1..8] OF ST_Recipe;
    selSlot : INT;
    loadCmd : BOOL;
    running : BOOL;
END_VAR
VAR_OUTPUT
    valid : BOOL;
    loadedID : INT;
END_VAR
VAR
    previousLoadCmd : BOOL := FALSE;
    previousValid : BOOL := FALSE;
    previousLoadedID : INT := 0;
    loadEdge : BOOL;
    slotInRange : BOOL;
    slotNonEmpty : BOOL;
    ratioInRange : BOOL;
    temperatureInRange : BOOL;
END_VAR

loadEdge := loadCmd AND NOT previousLoadCmd;

loadedID := previousLoadedID;
valid := previousValid;

IF loadEdge AND NOT running THEN
    slotInRange := (selSlot >= 1) AND (selSlot <= 8);

    IF slotInRange THEN
        slotNonEmpty := recipe[selSlot].recipeID <> 0;
        ratioInRange := (recipe[selSlot].totalRatio >= 99.0)
                        AND (recipe[selSlot].totalRatio <= 101.0);
        temperatureInRange := (recipe[selSlot].temperature >= 30.0)
                              AND (recipe[selSlot].temperature <= 180.0);

        IF slotNonEmpty AND ratioInRange AND temperatureInRange THEN
            valid := TRUE;
            loadedID := recipe[selSlot].recipeID;
        ELSE
            valid := FALSE;
            loadedID := 0;
        END_IF;
    ELSE
        valid := FALSE;
        loadedID := 0;
    END_IF;
END_IF;

previousLoadCmd := loadCmd;
previousValid := valid;
previousLoadedID := loadedID;
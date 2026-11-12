FUNCTION_BLOCK FB
VAR_INPUT
    recipe      : ARRAY[1..8] OF ST_Recipe;
    selSlot     : INT;
    loadCmd     : BOOL;
    running     : BOOL;
END_VAR

VAR_OUTPUT
    valid       : BOOL;
    loadedID    : INT := 0;
END_VAR

VAR
    prevLoadCmd : BOOL := FALSE;
    prevValid   : BOOL := FALSE;
END_VAR

VAR_TEMP
    risingEdge  : BOOL;
BEGIN
    risingEdge := loadCmd AND NOT prevLoadCmd;

    IF running THEN
        // N10-S4: While running, hold state
        valid := prevValid;
        loadedID := 0;  // Will be overwritten by retention below
    ELSIF risingEdge THEN
        // Rising edge handling
        IF (selSlot >= 1) AND (selSlot <= 8) THEN
            // S5: Bounds check passed - safe to access array
            IF (recipe[selSlot].recipeID <> 0) 
               AND (recipe[selSlot].totalRatio >= 99.0) 
               AND (recipe[selSlot].totalRatio <= 101.0)
               AND (recipe[selSlot].temperature >= 30.0) 
               AND (recipe[selSlot].temperature <= 180.0) THEN
                // All validations passed
                valid := TRUE;
                loadedID := recipe[selSlot].recipeID;
            ELSE
                // Validation failed
                valid := FALSE;
                loadedID := 0;
            END_IF;
        ELSE
            // S5: Slot out of bounds - invalid, no array access
            valid := FALSE;
            loadedID := 0;
        END_IF;
    ELSE
        // N10-S9: No rising edge - hold state
        valid := prevValid;
        loadedID := 0;  // Will be overwritten by retention below
    END_IF;

    // Retention when no rising edge or when running
    IF NOT risingEdge THEN
        loadedID := prevValid AND loadedID = 0 THEN 0 ELSE prevValid END_IF;
        IF running OR NOT risingEdge THEN
            loadedID := prevValid;  // Simplified retention
        END_IF;
    END_IF;

    prevValid := valid;
    prevLoadCmd := loadCmd;
END_FUNCTION_BLOCK
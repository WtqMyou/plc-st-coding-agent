FUNCTION_BLOCK FB
VAR_INPUT
    recipe   : ARRAY[1..8] OF ST_Recipe;
    selSlot  : INT;
    loadCmd  : BOOL;
    running  : BOOL;
END_VAR

VAR_OUTPUT
    valid    : BOOL;
    loadedID : INT;
END_VAR

VAR
    prevLoadCmd : BOOL := FALSE;
    prevRunning : BOOL := FALSE;
    prevValid   : BOOL := FALSE;
    prevLoadedID: INT  := 0;
END_VAR

VAR_TEMP
    risingEdge : BOOL;
    slotValid  : BOOL;
END_VAR

// Detect rising edge of loadCmd
risingEdge := loadCmd AND NOT prevLoadCmd;

// State retention: hold previous values unless explicitly updated
valid   := prevValid;
loadedID := prevLoadedID;

// Process load command only on rising edge and when not running
IF risingEdge AND NOT running THEN
    // Bounds check before array access
    IF (selSlot >= 1) AND (selSlot <= 8) THEN
        // Check all three validation conditions
        slotValid := (recipe[selSlot].recipeID <> 0)
                     AND (recipe[selSlot].totalRatio >= 99.0)
                     AND (recipe[selSlot].totalRatio <= 101.0)
                     AND (recipe[selSlot].temperature >= 30.0)
                     AND (recipe[selSlot].temperature <= 180.0);

        valid    := slotValid;
        loadedID := 0; // default on invalid
        IF slotValid THEN
            loadedID := recipe[selSlot].recipeID;
        END_IF;
    ELSE
        // Out-of-bounds: mark invalid, do not access array
        valid    := FALSE;
        loadedID := 0;
    END_IF;
END_IF;

// Update previous-cycle state for next scan
prevLoadCmd  := loadCmd;
prevRunning  := running;
prevValid    := valid;
prevLoadedID := loadedID;

END_FUNCTION_BLOCK
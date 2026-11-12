TYPE ST_Recipe : STRUCT
    recipeID    : INT;
    totalRatio  : REAL;
    temperature : REAL;
END_STRUCT
END_TYPE

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
    prevLoadCmd  : BOOL := FALSE;
    prevRunning  : BOOL := FALSE;
    prevValid    : BOOL := FALSE;
    prevLoadedID : INT  := 0;
END_VAR

VAR_TEMP
    curRecipeID  : INT;
    curRatio     : REAL;
    curTemp      : REAL;
    slotInBounds : BOOL;
    recipeNotEmpty : BOOL;
    ratioInRange : BOOL;
    tempInRange  : BOOL;
    loadValid    : BOOL;
END_VAR

// Default: retain previous state
valid    := prevValid;
loadedID := prevLoadedID;

// Rising edge detection of loadCmd
IF loadCmd AND NOT prevLoadCmd THEN
    // Only process when not running
    IF NOT running THEN
        // Bounds check before array access
        slotInBounds := (selSlot >= 1) AND (selSlot <= 8);
        
        IF slotInBounds THEN
            // Read values into temporaries
            curRecipeID := recipe[selSlot].recipeID;
            curRatio    := recipe[selSlot].totalRatio;
            curTemp     := recipe[selSlot].temperature;
            
            // Validate each condition
            recipeNotEmpty := (curRecipeID <> 0);
            ratioInRange   := (curRatio >= 99.0) AND (curRatio <= 101.0);
            tempInRange    := (curTemp >= 30.0) AND (curTemp <= 180.0);
            
            // Combined validation
            loadValid := recipeNotEmpty AND ratioInRange AND tempInRange;
            
            valid    := loadValid;
            IF loadValid THEN
                loadedID := curRecipeID;
            ELSE
                loadedID := 0;
            END_IF;
        ELSE
            // Out-of-bounds: invalid, no array access
            valid    := FALSE;
            loadedID := 0;
        END_IF;
    END_IF;
END_IF;

// Update previous-cycle state
prevLoadCmd  := loadCmd;
prevRunning  := running;
prevValid    := valid;
prevLoadedID := loadedID;

END_FUNCTION_BLOCK
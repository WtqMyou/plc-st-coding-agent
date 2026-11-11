TYPE ST_Recipe :
STRUCT
    recipeID: INT;
    totalRatio: REAL;
    temperature: REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    recipe: ARRAY[1..8] OF ST_Recipe;
    selSlot: INT;
    loadCmd: BOOL;
    running: BOOL;
END_VAR

VAR_OUTPUT
    valid: BOOL;
    loadedID: INT;
END_VAR

VAR
    prevLoadCmd: BOOL := FALSE;
    prevLoadedID: INT := 0;
    prevValid: BOOL := FALSE;
    risingEdge: BOOL;
END_VAR

risingEdge := loadCmd AND NOT prevLoadCmd;

IF risingEdge AND NOT running THEN
    IF (selSlot >= 1) AND (selSlot <= 8) THEN
        IF (recipe[selSlot].recipeID <> 0) AND
           (recipe[selSlot].totalRatio >= 99.0) AND
           (recipe[selSlot].totalRatio <= 101.0) AND
           (recipe[selSlot].temperature >= 30.0) AND
           (recipe[selSlot].temperature <= 180.0) THEN
            loadedID := recipe[selSlot].recipeID;
            valid := TRUE;
        ELSE
            loadedID := 0;
            valid := FALSE;
        END_IF
    ELSE
        loadedID := 0;
        valid := FALSE;
    END_IF;
ELSE
    IF running THEN
        loadedID := prevLoadedID;
        valid := prevValid;
    END_IF;
END_IF;

prevLoadedID := loadedID;
prevValid := valid;
prevLoadCmd := loadCmd;

END_FUNCTION_BLOCK
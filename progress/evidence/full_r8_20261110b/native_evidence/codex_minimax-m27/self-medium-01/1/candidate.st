TYPE ST_Recipe :
STRUCT
    recipeID    : INT;
    totalRatio  : REAL;
    temperature : REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    recipe    : ARRAY[1..8] OF ST_Recipe;
    selSlot   : INT;
    loadCmd   : BOOL;
    running   : BOOL;
END_VAR
VAR_OUTPUT
    valid     : BOOL;
    loadedID  : INT;
END_VAR
VAR
    prevLoadCmd  : BOOL := FALSE;
    prevLoadedID : INT  := 0;
    prevValid    : BOOL := FALSE;
END_VAR

IF running THEN
    loadedID := prevLoadedID;
    valid := prevValid;
ELSIF NOT prevLoadCmd AND loadCmd THEN
    IF (selSlot < 1) OR (selSlot > 8) THEN
        valid := FALSE;
        loadedID := 0;
    ELSE
        valid := (recipe[selSlot].recipeID <> 0)
                 AND (recipe[selSlot].totalRatio >= 99.0)
                 AND (recipe[selSlot].totalRatio <= 101.0)
                 AND (recipe[selSlot].temperature >= 30.0)
                 AND (recipe[selSlot].temperature <= 180.0);
        IF valid THEN
            loadedID := recipe[selSlot].recipeID;
        ELSE
            loadedID := 0;
        END_IF
    END_IF
ELSE
    loadedID := prevLoadedID;
    valid := prevValid;
END_IF

prevLoadCmd  := loadCmd;
prevLoadedID := loadedID;
prevValid    := valid;
END_FUNCTION_BLOCK
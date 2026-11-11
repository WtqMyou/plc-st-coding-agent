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
    loadCmdPrev : BOOL;
    lastValid : BOOL;
END_VAR

IF running THEN
    valid := lastValid;
ELSIF loadCmd AND NOT loadCmdPrev THEN
    IF selSlot >= 1 AND selSlot <= 8 THEN
        IF recipe[selSlot].recipeID <> 0
           AND recipe[selSlot].totalRatio >= 99.0
           AND recipe[selSlot].totalRatio <= 101.0
           AND recipe[selSlot].temperature >= 30.0
           AND recipe[selSlot].temperature <= 180.0 THEN
            valid := TRUE;
            loadedID := recipe[selSlot].recipeID;
        ELSE
            valid := FALSE;
            loadedID := 0;
        END_IF
    ELSE
        valid := FALSE;
        loadedID := 0;
    END_IF
ELSE
    valid := lastValid;
END_IF

loadCmdPrev := loadCmd;
lastValid := valid;
END_FUNCTION_BLOCK
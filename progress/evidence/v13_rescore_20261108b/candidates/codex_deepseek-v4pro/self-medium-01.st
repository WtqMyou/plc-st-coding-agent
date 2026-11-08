TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    totalRatio : REAL;
    temperature : REAL;
END_STRUCT
END_TYPE

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
    lastLoadCmd : BOOL;
    loadRising : BOOL;
    slotValid : BOOL;
END_VAR

loadRising := loadCmd AND NOT lastLoadCmd;
slotValid := (selSlot >= 1) AND (selSlot <= 8);

IF running THEN
    valid := FALSE;
ELSIF loadRising THEN
    IF NOT slotValid THEN
        valid := FALSE;
        loadedID := 0;
    ELSIF recipe[selSlot].recipeID = 0 THEN
        valid := FALSE;
    ELSIF (recipe[selSlot].totalRatio < 99.0) OR (recipe[selSlot].totalRatio > 101.0) THEN
        valid := FALSE;
        loadedID := 0;
    ELSIF (recipe[selSlot].temperature < 30.0) OR (recipe[selSlot].temperature > 180.0) THEN
        valid := FALSE;
        loadedID := 0;
    ELSE
        valid := TRUE;
        loadedID := recipe[selSlot].recipeID;
    END_IF
END_IF

lastLoadCmd := loadCmd;

END_FUNCTION_BLOCK
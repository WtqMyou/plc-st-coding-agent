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
    lastLoadCmd : BOOL := FALSE;
    memValid : BOOL := FALSE;
    memLoadedID : INT := 0;
    risingEdge : BOOL;
END_VAR

risingEdge := loadCmd AND NOT lastLoadCmd;
lastLoadCmd := loadCmd;

IF risingEdge AND NOT running THEN
    IF (selSlot < 1) OR (selSlot > 8) THEN
        memValid := FALSE;
        memLoadedID := 0;
    ELSE
        IF recipe[selSlot].recipeID = 0 THEN
            memValid := FALSE;
            memLoadedID := 0;
        ELSIF (recipe[selSlot].totalRatio < 99.0) OR (recipe[selSlot].totalRatio > 101.0) THEN
            memValid := FALSE;
            memLoadedID := 0;
        ELSIF (recipe[selSlot].temperature < 30.0) OR (recipe[selSlot].temperature > 180.0) THEN
            memValid := FALSE;
            memLoadedID := 0;
        ELSE
            memValid := TRUE;
            memLoadedID := recipe[selSlot].recipeID;
        END_IF
    END_IF
END_IF

valid := memValid;
loadedID := memLoadedID;

END_FUNCTION_BLOCK
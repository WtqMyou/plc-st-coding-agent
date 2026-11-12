TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    totalRatio : REAL;
    temperature : REAL;
END_STRUCT
END_TYPE;

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
    loadCmdPrevious : BOOL;
    loadEdge : BOOL;
    slotInRange : BOOL;
    ratioInRange : BOOL;
    tempInRange : BOOL;
    slotOccupied : BOOL;
    latchedValid : BOOL;
    latchedLoadedID : INT;
END_VAR

loadEdge := loadCmd AND NOT loadCmdPrevious;

IF loadEdge AND NOT running THEN
    slotInRange := (selSlot >= 1) AND (selSlot <= 8);

    IF slotInRange THEN
        slotOccupied := (recipe[selSlot].recipeID <> 0);
        ratioInRange := (recipe[selSlot].totalRatio >= 99.0) AND
                        (recipe[selSlot].totalRatio <= 101.0);
        tempInRange := (recipe[selSlot].temperature >= 30.0) AND
                       (recipe[selSlot].temperature <= 180.0);

        latchedValid := slotOccupied AND ratioInRange AND tempInRange;

        IF latchedValid THEN
            latchedLoadedID := recipe[selSlot].recipeID;
        ELSE
            latchedLoadedID := 0;
        END_IF;
    ELSE
        latchedValid := FALSE;
        latchedLoadedID := 0;
    END_IF;
END_IF;

valid := latchedValid;
loadedID := latchedLoadedID;
loadCmdPrevious := loadCmd;

END_FUNCTION_BLOCK
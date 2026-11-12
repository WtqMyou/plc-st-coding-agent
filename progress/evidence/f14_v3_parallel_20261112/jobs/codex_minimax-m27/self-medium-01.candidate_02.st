TYPE ST_Recipe :
STRUCT
    recipeID    : INT;
    totalRatio  : REAL;
    temperature : REAL;
END_STRUCT;
END_TYPE;

FUNCTION_BLOCK FB
VAR_INPUT
    recipe      : ARRAY[1..8] OF ST_Recipe;
    selSlot     : INT;
    loadCmd     : BOOL;
    running     : BOOL;
END_VAR

VAR_OUTPUT
    valid       : BOOL := FALSE;
    loadedID    : INT := 0;
END_VAR

VAR
    prevLoadCmd : BOOL := FALSE;
    prevRunning : BOOL := FALSE;
END_VAR

BEGIN
    IF loadCmd AND NOT prevLoadCmd THEN
        IF NOT running THEN
            IF (selSlot >= 1) AND (selSlot <= 8) THEN
                IF (recipe[selSlot].recipeID <> 0) AND
                   (recipe[selSlot].totalRatio >= 99.0) AND
                   (recipe[selSlot].totalRatio <= 101.0) AND
                   (recipe[selSlot].temperature >= 30.0) AND
                   (recipe[selSlot].temperature <= 180.0) THEN
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
    END_IF;

    IF running AND NOT prevRunning THEN
        loadedID := loadedID;
    END_IF;

    prevLoadCmd := loadCmd;
    prevRunning := running;
END_FUNCTION_BLOCK
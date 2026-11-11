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
    currentValid : BOOL;
    currentLoadedID : INT;
    tempRecipeID : INT;
    tempTotalRatio : REAL;
    tempTemperature : REAL;
END_VAR
    currentValid := valid;
    currentLoadedID := loadedID;

    IF NOT running AND loadCmd AND NOT lastLoadCmd THEN
        IF selSlot >= 1 AND selSlot <= 8 THEN
            tempRecipeID := recipe[selSlot].recipeID;
            tempTotalRatio := recipe[selSlot].totalRatio;
            tempTemperature := recipe[selSlot].temperature;

            IF tempRecipeID <> 0 AND tempTotalRatio >= 99.0 AND tempTotalRatio <= 101.0 AND tempTemperature >= 30.0 AND tempTemperature <= 180.0 THEN
                currentValid := TRUE;
                currentLoadedID := tempRecipeID;
            ELSE
                currentValid := FALSE;
                currentLoadedID := 0;
            END_IF
        ELSE
            currentValid := FALSE;
            currentLoadedID := 0;
        END_IF
    END_IF

    valid := currentValid;
    loadedID := currentLoadedID;

    lastLoadCmd := loadCmd;
END_FUNCTION_BLOCK
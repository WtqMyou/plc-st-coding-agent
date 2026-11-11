TYPE ST_Recipe :
STRUCT
    recipeID                : INT;
    ingredientType          : INT;
    ingredientRatio         : REAL;
    productionTemperature   : REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    addRecipe      : BOOL;
    deleteRecipe   : BOOL;
    modifyRecipe   : BOOL;
    queryRecipe    : BOOL;
    recipeIn       : ST_Recipe;
END_VAR
VAR_OUTPUT
    recipeAdded          : BOOL;
    recipeDeleted        : BOOL;
    recipeModified       : BOOL;
    recipeQueryResult    : ST_Recipe;
    error                : BOOL;
    status               : WORD;
END_VAR
VAR_IN_OUT
    recipe : ARRAY[1..10] OF ST_Recipe;
END_VAR
VAR
    prevAddRecipe    : BOOL := FALSE;
    prevDeleteRecipe : BOOL := FALSE;
    prevModifyRecipe : BOOL := FALSE;
    prevQueryRecipe  : BOOL := FALSE;
    risingAdd        : BOOL;
    risingDelete     : BOOL;
    risingModify     : BOOL;
    risingQuery      : BOOL;
    i                : INT;
    duplicateFound   : BOOL;
    emptySlotIndex   : INT;
    found            : BOOL;
END_VAR

    risingAdd    := addRecipe AND NOT prevAddRecipe;
    risingDelete := deleteRecipe AND NOT prevDeleteRecipe;
    risingModify := modifyRecipe AND NOT prevModifyRecipe;
    risingQuery  := queryRecipe AND NOT prevQueryRecipe;

    prevAddRecipe    := addRecipe;
    prevDeleteRecipe := deleteRecipe;
    prevModifyRecipe := modifyRecipe;
    prevQueryRecipe  := queryRecipe;

    recipeAdded     := FALSE;
    recipeDeleted   := FALSE;
    recipeModified  := FALSE;
    recipeQueryResult.recipeID := 0;
    error           := FALSE;
    status          := 16#0000;

    IF risingQuery THEN
        error := TRUE;
        status := 16#8001;
        IF recipeIn.recipeID <> 0 THEN
            FOR i := 1 TO 10 DO
                IF recipe[i].recipeID = recipeIn.recipeID THEN
                    recipeQueryResult := recipe[i];
                    error   := FALSE;
                    status  := 16#0000;
                    EXIT;
                END_IF
            END_FOR
        END_IF
    ELSIF risingAdd THEN
        IF recipeIn.recipeID <> 0 THEN
            duplicateFound := FALSE;
            emptySlotIndex := 0;
            FOR i := 1 TO 10 DO
                IF recipe[i].recipeID = recipeIn.recipeID THEN
                    duplicateFound := TRUE;
                    EXIT;
                END_IF
            END_FOR
            IF duplicateFound THEN
                error  := TRUE;
                status := 16#8002;
            ELSE
                FOR i := 1 TO 10 DO
                    IF recipe[i].recipeID = 0 THEN
                        emptySlotIndex := i;
                        EXIT;
                    END_IF
                END_FOR
                IF emptySlotIndex = 0 THEN
                    error  := TRUE;
                    status := 16#8003;
                ELSE
                    recipe[emptySlotIndex] := recipeIn;
                    recipeAdded := TRUE;
                END_IF
            END_IF
        END_IF
    ELSIF risingDelete THEN
        IF recipeIn.recipeID <> 0 THEN
            found := FALSE;
            FOR i := 1 TO 10 DO
                IF recipe[i].recipeID = recipeIn.recipeID THEN
                    recipe[i].recipeID := 0;
                    recipeDeleted := TRUE;
                    found := TRUE;
                    EXIT;
                END_IF
            END_FOR
            IF NOT found THEN
                error  := TRUE;
                status := 16#8004;
            END_IF
        END_IF
    ELSIF risingModify THEN
        IF recipeIn.recipeID <> 0 THEN
            found := FALSE;
            FOR i := 1 TO 10 DO
                IF recipe[i].recipeID = recipeIn.recipeID THEN
                    recipe[i] := recipeIn;
                    recipeModified := TRUE;
                    found := TRUE;
                    EXIT;
                END_IF
            END_FOR
            IF NOT found THEN
                error  := TRUE;
                status := 16#8005;
            END_IF
        END_IF
    END_IF
END_FUNCTION_BLOCK
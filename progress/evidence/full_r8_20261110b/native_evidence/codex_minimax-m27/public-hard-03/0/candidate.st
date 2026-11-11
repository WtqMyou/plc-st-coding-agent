FUNCTION_BLOCK FB
VAR_INPUT
    addRecipe : BOOL;
    deleteRecipe : BOOL;
    modifyRecipe : BOOL;
    queryRecipe : BOOL;
    recipeIn : ST_Recipe;
END_VAR
VAR_OUTPUT
    recipeAdded : BOOL := FALSE;
    recipeDeleted : BOOL := FALSE;
    recipeModified : BOOL := FALSE;
    recipeQueryResult : ST_Recipe;
    error : BOOL := FALSE;
    status : WORD := 16#0000;
END_VAR
VAR_IN_OUT
    recipe : ARRAY[1..10] OF ST_Recipe;
END_VAR
VAR
    prevAddRecipe : BOOL := FALSE;
    prevDeleteRecipe : BOOL := FALSE;
    prevModifyRecipe : BOOL := FALSE;
    prevQueryRecipe : BOOL := FALSE;
    i : INT;
END_VAR

recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 16#0000;

IF queryRecipe AND NOT prevQueryRecipe THEN
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            recipeQueryResult := recipe[i];
            EXIT;
        END_IF
    END_FOR
    IF recipeQueryResult.recipeID <> recipeIn.recipeID THEN
        error := TRUE;
        status := 16#8001;
    END_IF
    RETURN;
END_IF

IF addRecipe AND NOT prevAddRecipe THEN
    IF recipeIn.recipeID <> 0 THEN
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID = recipeIn.recipeID THEN
                error := TRUE;
                status := 16#8002;
                RETURN;
            END_IF
        END_FOR
    END_IF
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = 0 THEN
            recipe[i] := recipeIn;
            recipeAdded := TRUE;
            RETURN;
        END_IF
    END_FOR
    error := TRUE;
    status := 16#8003;
    RETURN;
END_IF

IF deleteRecipe AND NOT prevDeleteRecipe THEN
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            recipe[i].recipeID := 0;
            recipeDeleted := TRUE;
            RETURN;
        END_IF
    END_FOR
    error := TRUE;
    status := 16#8004;
    RETURN;
END_IF

IF modifyRecipe AND NOT prevModifyRecipe THEN
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            recipe[i].ingredientType := recipeIn.ingredientType;
            recipe[i].ingredientRatio := recipeIn.ingredientRatio;
            recipe[i].productionTemperature := recipeIn.productionTemperature;
            recipeModified := TRUE;
            RETURN;
        END_IF
    END_FOR
    error := TRUE;
    status := 16#8005;
    RETURN;
END_IF

prevQueryRecipe := queryRecipe;
prevAddRecipe := addRecipe;
prevDeleteRecipe := deleteRecipe;
prevModifyRecipe := modifyRecipe;
END_FUNCTION_BLOCK
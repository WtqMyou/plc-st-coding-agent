TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    ingredientType : INT;
    ingredientRatio : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
    addRecipe : BOOL;
    deleteRecipe : BOOL;
    modifyRecipe : BOOL;
    queryRecipe : BOOL;
    recipeIn : ST_Recipe;
END_VAR

VAR_OUTPUT
    recipeAdded : BOOL;
    recipeDeleted : BOOL;
    recipeModified : BOOL;
    recipeQueryResult : ST_Recipe;
    error : BOOL;
    status : WORD;
END_VAR

VAR_IN_OUT
    recipe : ARRAY[1..10] OF ST_Recipe;
END_VAR

VAR
    addRecipe_prev : BOOL;
    deleteRecipe_prev : BOOL;
    modifyRecipe_prev : BOOL;
    queryRecipe_prev : BOOL;
END_VAR

VAR_TEMP
    idx : INT;
    foundIdx : INT;
    emptyIdx : INT;
    isFound : BOOL;
    hasEmpty : BOOL;
END_VAR

    recipeAdded := FALSE;
    recipeDeleted := FALSE;
    recipeModified := FALSE;
    error := FALSE;
    status := 16#0000;

    IF addRecipe AND NOT addRecipe_prev THEN
        isFound := FALSE;
        FOR idx := 1 TO 10 DO
            IF recipe[idx].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                isFound := TRUE;
                EXIT;
            END_IF
        END_FOR

        IF isFound THEN
            error := TRUE;
            status := 16#8002;
        ELSE
            hasEmpty := FALSE;
            emptyIdx := 0;
            FOR idx := 1 TO 10 DO
                IF recipe[idx].recipeID = 0 THEN
                    hasEmpty := TRUE;
                    emptyIdx := idx;
                    EXIT;
                END_IF
            END_FOR

            IF hasEmpty THEN
                recipe[emptyIdx] := recipeIn;
                error := FALSE;
                status := 16#0000;
                recipeAdded := TRUE;
            ELSE
                error := TRUE;
                status := 16#8003;
            END_IF
        END_IF;

    ELSIF deleteRecipe AND NOT deleteRecipe_prev THEN
        isFound := FALSE;
        foundIdx := 0;
        FOR idx := 1 TO 10 DO
            IF recipe[idx].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                isFound := TRUE;
                foundIdx := idx;
                EXIT;
            END_IF
        END_FOR

        IF isFound THEN
            recipe[foundIdx].recipeID := 0;
            recipe[foundIdx].ingredientType := 0;
            recipe[foundIdx].ingredientRatio := 0.0;
            recipe[foundIdx].productionTemperature := 0.0;
            error := FALSE;
            status := 16#0000;
            recipeDeleted := TRUE;
        ELSE
            error := TRUE;
            status := 16#8004;
        END_IF;

    ELSIF modifyRecipe AND NOT modifyRecipe_prev THEN
        isFound := FALSE;
        foundIdx := 0;
        FOR idx := 1 TO 10 DO
            IF recipe[idx].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                isFound := TRUE;
                foundIdx := idx;
                EXIT;
            END_IF
        END_FOR

        IF isFound THEN
            recipe[foundIdx] := recipeIn;
            error := FALSE;
            status := 16#0000;
            recipeModified := TRUE;
        ELSE
            error := TRUE;
            status := 16#8005;
        END_IF;

    ELSIF queryRecipe AND NOT queryRecipe_prev THEN
        isFound := FALSE;
        foundIdx := 0;
        FOR idx := 1 TO 10 DO
            IF recipe[idx].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                isFound := TRUE;
                foundIdx := idx;
                EXIT;
            END_IF
        END_FOR

        IF isFound THEN
            recipeQueryResult := recipe[foundIdx];
            error := FALSE;
            status := 16#0000;
        ELSE
            recipeQueryResult.recipeID := 0;
            recipeQueryResult.ingredientType := 0;
            recipeQueryResult.ingredientRatio := 0.0;
            recipeQueryResult.productionTemperature := 0.0;
            error := TRUE;
            status := 16#8001;
        END_IF;
    END_IF

    addRecipe_prev := addRecipe;
    deleteRecipe_prev := deleteRecipe;
    modifyRecipe_prev := modifyRecipe;
    queryRecipe_prev := queryRecipe;

END_FUNCTION_BLOCK
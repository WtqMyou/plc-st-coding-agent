TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    ingredientType : INT;
    ingredientRatio : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK RecipeManagement
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
    i : INT;
    foundIndex : INT;
    emptyIndex : INT;
    duplicate : BOOL;
END_VAR

    recipeAdded := FALSE;
    recipeDeleted := FALSE;
    recipeModified := FALSE;
    error := FALSE;
    status := 0;
    recipeQueryResult.recipeID := 0;
    recipeQueryResult.ingredientType := 0;
    recipeQueryResult.ingredientRatio := 0.0;
    recipeQueryResult.productionTemperature := 0.0;
    duplicate := FALSE;
    foundIndex := 0;
    emptyIndex := 0;

    IF addRecipe THEN
        duplicate := FALSE;
        foundIndex := 0;
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID <> 0 AND recipe[i].recipeID = recipeIn.recipeID THEN
                duplicate := TRUE;
                foundIndex := i;
                EXIT;
            END_IF;
        END_FOR;

        IF duplicate THEN
            error := TRUE;
            status := 16#8002;
        ELSE
            emptyIndex := 0;
            FOR i := 1 TO 10 DO
                IF recipe[i].recipeID = 0 THEN
                    emptyIndex := i;
                    EXIT;
                END_IF;
            END_FOR;
            IF emptyIndex = 0 THEN
                error := TRUE;
                status := 16#8003;
            ELSE
                recipe[emptyIndex] := recipeIn;
                recipeAdded := TRUE;
            END_IF;
        END_IF;

    ELSIF deleteRecipe THEN
        foundIndex := 0;
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID <> 0 AND recipe[i].recipeID = recipeIn.recipeID THEN
                foundIndex := i;
                EXIT;
            END_IF;
        END_FOR;
        IF foundIndex = 0 THEN
            error := TRUE;
            status := 16#8004;
        ELSE
            recipe[foundIndex].recipeID := 0;
            recipe[foundIndex].ingredientType := 0;
            recipe[foundIndex].ingredientRatio := 0.0;
            recipe[foundIndex].productionTemperature := 0.0;
            recipeDeleted := TRUE;
        END_IF;

    ELSIF modifyRecipe THEN
        foundIndex := 0;
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID <> 0 AND recipe[i].recipeID = recipeIn.recipeID THEN
                foundIndex := i;
                EXIT;
            END_IF;
        END_FOR;
        IF foundIndex = 0 THEN
            error := TRUE;
            status := 16#8005;
        ELSE
            recipe[foundIndex] := recipeIn;
            recipeModified := TRUE;
        END_IF;

    ELSIF queryRecipe THEN
        foundIndex := 0;
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID <> 0 AND recipe[i].recipeID = recipeIn.recipeID THEN
                foundIndex := i;
                EXIT;
            END_IF;
        END_FOR;
        IF foundIndex = 0 THEN
            error := TRUE;
            status := 16#8001;
        ELSE
            recipeQueryResult := recipe[foundIndex];
        END_IF;
    END_IF;

END_FUNCTION_BLOCK
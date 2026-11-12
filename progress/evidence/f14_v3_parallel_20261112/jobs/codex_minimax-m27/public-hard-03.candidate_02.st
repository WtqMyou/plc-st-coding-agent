TYPE ST_Recipe :
STRUCT
    recipeID : INT
    ingredientType : INT
    ingredientRatio : REAL
    productionTemperature : REAL
END_STRUCT;
END_TYPE;

FUNCTION_BLOCK RecipeManager
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
    prevAddRecipe : BOOL;
    prevDeleteRecipe : BOOL;
    prevModifyRecipe : BOOL;
    prevQueryRecipe : BOOL;
    i : INT;
    foundIndex : INT;
    emptySlotIndex : INT;
END_VAR

IF prevAddRecipe = FALSE AND prevDeleteRecipe = FALSE AND
   prevModifyRecipe = FALSE AND prevQueryRecipe = FALSE THEN
    FOR i := 1 TO 10 DO
        recipe[i].recipeID := 0;
    END_FOR;
END_IF;

recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 16#0000;

IF queryRecipe AND NOT prevQueryRecipe THEN
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            foundIndex := i;
            EXIT;
        END_IF;
    END_FOR;

    IF foundIndex > 0 THEN
        recipeQueryResult := recipe[foundIndex];
    ELSE
        error := TRUE;
        status := 16#8001;
    END_IF;

ELSIF addRecipe AND NOT prevAddRecipe THEN
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            foundIndex := i;
            EXIT;
        END_IF;
    END_FOR;

    IF foundIndex > 0 THEN
        error := TRUE;
        status := 16#8002;
    ELSE
        emptySlotIndex := 0;
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID = 0 THEN
                emptySlotIndex := i;
                EXIT;
            END_IF;
        END_FOR;

        IF emptySlotIndex = 0 THEN
            error := TRUE;
            status := 16#8003;
        ELSE
            recipe[emptySlotIndex] := recipeIn;
            recipeAdded := TRUE;
        END_IF;
    END_IF;

ELSIF deleteRecipe AND NOT prevDeleteRecipe THEN
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            foundIndex := i;
            EXIT;
        END_IF;
    END_FOR;

    IF foundIndex = 0 THEN
        error := TRUE;
        status := 16#8004;
    ELSE
        recipe[foundIndex].recipeID := 0;
        recipeDeleted := TRUE;
    END_IF;

ELSIF modifyRecipe AND NOT prevModifyRecipe THEN
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
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
END_IF;

prevAddRecipe := addRecipe;
prevDeleteRecipe := deleteRecipe;
prevModifyRecipe := modifyRecipe;
prevQueryRecipe := queryRecipe;

END_FUNCTION_BLOCK
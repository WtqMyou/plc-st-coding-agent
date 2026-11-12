TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    ingredientType : INT;
    ingredientRatio : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK RecipeManagement
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
    i : INT;
    foundIndex : INT;
    duplicateExists : BOOL;
    emptySlotIndex : INT;
END_VAR

recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
recipeQueryResult.recipeID := 0;
recipeQueryResult.ingredientType := 0;
recipeQueryResult.ingredientRatio := 0.0;
recipeQueryResult.productionTemperature := 0.0;
error := FALSE;
status := 16#0000;
foundIndex := 0;
duplicateExists := FALSE;
emptySlotIndex := 0;

IF addRecipe THEN
    duplicateExists := FALSE;
    emptySlotIndex := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
            duplicateExists := TRUE;
            EXIT;
        END_IF
        IF recipe[i].recipeID = 0 AND emptySlotIndex = 0 THEN
            emptySlotIndex := i;
        END_IF
    END_FOR;
    
    IF duplicateExists THEN
        error := TRUE;
        status := 16#8002;
    ELSIF emptySlotIndex = 0 THEN
        error := TRUE;
        status := 16#8003;
    ELSE
        recipe[emptySlotIndex].recipeID := recipeIn.recipeID;
        recipe[emptySlotIndex].ingredientType := recipeIn.ingredientType;
        recipe[emptySlotIndex].ingredientRatio := recipeIn.ingredientRatio;
        recipe[emptySlotIndex].productionTemperature := recipeIn.productionTemperature;
        recipeAdded := TRUE;
    END_IF;
END_IF;

IF deleteRecipe THEN
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            foundIndex := i;
            EXIT;
        END_IF
    END_FOR;
    
    IF foundIndex = 0 THEN
        error := TRUE;
        status := 16#8004;
    ELSE
        recipe[foundIndex].recipeID := 0;
        recipeDeleted := TRUE;
    END_IF;
END_IF;

IF modifyRecipe THEN
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            foundIndex := i;
            EXIT;
        END_IF
    END_FOR;
    
    IF foundIndex = 0 THEN
        error := TRUE;
        status := 16#8005;
    ELSE
        recipe[foundIndex].recipeID := recipeIn.recipeID;
        recipe[foundIndex].ingredientType := recipeIn.ingredientType;
        recipe[foundIndex].ingredientRatio := recipeIn.ingredientRatio;
        recipe[foundIndex].productionTemperature := recipeIn.productionTemperature;
        recipeModified := TRUE;
    END_IF;
END_IF;

IF queryRecipe THEN
    foundIndex := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            foundIndex := i;
            EXIT;
        END_IF
    END_FOR;
    
    IF foundIndex = 0 THEN
        error := TRUE;
        status := 16#8001;
    ELSE
        recipeQueryResult.recipeID := recipe[foundIndex].recipeID;
        recipeQueryResult.ingredientType := recipe[foundIndex].ingredientType;
        recipeQueryResult.ingredientRatio := recipe[foundIndex].ingredientRatio;
        recipeQueryResult.productionTemperature := recipe[foundIndex].productionTemperature;
    END_IF;
END_IF;
END_FUNCTION_BLOCK
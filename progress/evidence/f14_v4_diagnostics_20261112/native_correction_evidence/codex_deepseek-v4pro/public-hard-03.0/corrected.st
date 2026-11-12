TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    ingredientType : INT;
    ingredientRatio : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK RecipeManagementSystem
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
    found : BOOL;
    emptyIndex : INT;
    emptyFound : BOOL;
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

found := FALSE;
foundIndex := 0;
FOR i := 1 TO 10 BY 1 DO
    IF recipe[i].recipeID = recipeIn.recipeID THEN
        found := TRUE;
        foundIndex := i;
        EXIT;
    END_IF;
END_FOR;

IF addRecipe THEN
    emptyFound := FALSE;
    emptyIndex := 0;
    FOR i := 1 TO 10 BY 1 DO
        IF recipe[i].recipeID = 0 THEN
            emptyFound := TRUE;
            emptyIndex := i;
            EXIT;
        END_IF;
    END_FOR;

    IF found THEN
        error := TRUE;
        status := 16#8002;
    ELSIF NOT emptyFound THEN
        error := TRUE;
        status := 16#8003;
    ELSE
        recipe[emptyIndex] := recipeIn;
        recipeAdded := TRUE;
    END_IF;

ELSIF deleteRecipe THEN
    IF NOT found THEN
        error := TRUE;
        status := 16#8004;
    ELSE
        recipe[foundIndex].recipeID := 0;
        recipeDeleted := TRUE;
    END_IF;

ELSIF modifyRecipe THEN
    IF NOT found THEN
        error := TRUE;
        status := 16#8005;
    ELSE
        recipe[foundIndex] := recipeIn;
        recipeModified := TRUE;
    END_IF;

ELSIF queryRecipe THEN
    IF NOT found THEN
        error := TRUE;
        status := 16#8001;
    ELSE
        recipeQueryResult := recipe[foundIndex];
    END_IF;
END_IF;
END_FUNCTION_BLOCK
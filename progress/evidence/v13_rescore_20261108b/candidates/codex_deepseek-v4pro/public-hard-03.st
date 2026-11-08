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
    lastAddRecipe : BOOL;
    lastDeleteRecipe : BOOL;
    lastModifyRecipe : BOOL;
    lastQueryRecipe : BOOL;
    addEdge : BOOL;
    deleteEdge : BOOL;
    modifyEdge : BOOL;
    queryEdge : BOOL;
    i : INT;
    foundIndex : INT;
    emptyIndex : INT;
    recipeFound : BOOL;
END_VAR

recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;

addEdge := addRecipe AND NOT lastAddRecipe;
deleteEdge := deleteRecipe AND NOT lastDeleteRecipe;
modifyEdge := modifyRecipe AND NOT lastModifyRecipe;
queryEdge := queryRecipe AND NOT lastQueryRecipe;

IF addEdge OR deleteEdge OR modifyEdge OR queryEdge THEN
    error := FALSE;
    status := WORD#0;
END_IF

IF queryEdge THEN
    recipeFound := FALSE;
    foundIndex := 0;

    FOR i := 1 TO 10 DO
        IF (recipeIn.recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
            recipeFound := TRUE;
            foundIndex := i;
        END_IF
    END_FOR

    IF recipeFound THEN
        recipeQueryResult := recipe[foundIndex];
    ELSE
        error := TRUE;
        status := WORD#16#8001;
        recipeQueryResult.recipeID := 0;
        recipeQueryResult.ingredientType := 0;
        recipeQueryResult.ingredientRatio := 0.0;
        recipeQueryResult.productionTemperature := 0.0;
    END_IF
END_IF

IF addEdge THEN
    recipeFound := FALSE;
    emptyIndex := 0;

    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            recipeFound := TRUE;
        END_IF

        IF (recipe[i].recipeID = 0) AND (emptyIndex = 0) THEN
            emptyIndex := i;
        END_IF
    END_FOR

    IF recipeFound THEN
        error := TRUE;
        status := WORD#16#8002;
    ELSIF emptyIndex = 0 THEN
        error := TRUE;
        status := WORD#16#8003;
    ELSE
        recipe[emptyIndex] := recipeIn;
        recipeAdded := TRUE;
    END_IF
END_IF

IF deleteEdge THEN
    recipeFound := FALSE;
    foundIndex := 0;

    FOR i := 1 TO 10 DO
        IF (recipeIn.recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
            recipeFound := TRUE;
            foundIndex := i;
        END_IF
    END_FOR

    IF recipeFound THEN
        recipe[foundIndex].recipeID := 0;
        recipeDeleted := TRUE;
    ELSE
        error := TRUE;
        status := WORD#16#8004;
    END_IF
END_IF

IF modifyEdge THEN
    recipeFound := FALSE;
    foundIndex := 0;

    FOR i := 1 TO 10 DO
        IF (recipeIn.recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
            recipeFound := TRUE;
            foundIndex := i;
        END_IF
    END_FOR

    IF recipeFound THEN
        recipe[foundIndex] := recipeIn;
        recipeModified := TRUE;
    ELSE
        error := TRUE;
        status := WORD#16#8005;
    END_IF
END_IF

lastAddRecipe := addRecipe;
lastDeleteRecipe := deleteRecipe;
lastModifyRecipe := modifyRecipe;
lastQueryRecipe := queryRecipe;
END_FUNCTION_BLOCK
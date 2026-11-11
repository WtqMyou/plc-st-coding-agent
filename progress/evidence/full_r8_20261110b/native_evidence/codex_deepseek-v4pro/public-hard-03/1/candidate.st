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
    edgeAdd : BOOL;
    edgeDelete : BOOL;
    edgeModify : BOOL;
    edgeQuery : BOOL;
    lastAdd : BOOL;
    lastDelete : BOOL;
    lastModify : BOOL;
    lastQuery : BOOL;
    i : INT;
    found : BOOL;
    targetIndex : INT;
    emptyIndex : INT;
    internalError : BOOL;
    errorStatus : WORD;
END_VAR

recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 0;
internalError := FALSE;
errorStatus := 0;

edgeAdd := addRecipe AND NOT lastAdd;
edgeDelete := deleteRecipe AND NOT lastDelete;
edgeModify := modifyRecipe AND NOT lastModify;
edgeQuery := queryRecipe AND NOT lastQuery;

IF edgeQuery THEN
    found := FALSE;
    targetIndex := 0;

    FOR i := 1 TO 10 BY 1 DO
        IF (recipe[i].recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
            IF NOT found THEN
                found := TRUE;
                targetIndex := i;
            END_IF
        END_IF
    END_FOR

    IF found THEN
        recipeQueryResult := recipe[targetIndex];
        internalError := FALSE;
        errorStatus := 0;
    ELSE
        internalError := TRUE;
        errorStatus := 16#8001;
    END_IF
END_IF

IF edgeAdd THEN
    found := FALSE;

    FOR i := 1 TO 10 BY 1 DO
        IF (recipe[i].recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
            found := TRUE;
        END_IF
    END_FOR

    IF (recipeIn.recipeID = 0) OR found THEN
        internalError := TRUE;
        errorStatus := 16#8002;
    ELSE
        emptyIndex := 0;

        FOR i := 1 TO 10 BY 1 DO
            IF (recipe[i].recipeID = 0) AND (emptyIndex = 0) THEN
                emptyIndex := i;
            END_IF
        END_FOR

        IF emptyIndex = 0 THEN
            internalError := TRUE;
            errorStatus := 16#8003;
        ELSE
            recipe[emptyIndex] := recipeIn;
            recipeAdded := TRUE;
        END_IF
    END_IF
END_IF

IF edgeDelete THEN
    found := FALSE;
    targetIndex := 0;

    FOR i := 1 TO 10 BY 1 DO
        IF (recipe[i].recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
            IF NOT found THEN
                found := TRUE;
                targetIndex := i;
            END_IF
        END_IF
    END_FOR

    IF found THEN
        recipe[targetIndex].recipeID := 0;
        recipe[targetIndex].ingredientType := 0;
        recipe[targetIndex].ingredientRatio := 0.0;
        recipe[targetIndex].productionTemperature := 0.0;
        recipeDeleted := TRUE;
    ELSE
        internalError := TRUE;
        errorStatus := 16#8004;
    END_IF
END_IF

IF edgeModify THEN
    found := FALSE;
    targetIndex := 0;

    FOR i := 1 TO 10 BY 1 DO
        IF (recipe[i].recipeID <> 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
            IF NOT found THEN
                found := TRUE;
                targetIndex := i;
            END_IF
        END_IF
    END_FOR

    IF found THEN
        recipe[targetIndex] := recipeIn;
        recipeModified := TRUE;
    ELSE
        internalError := TRUE;
        errorStatus := 16#8005;
    END_IF
END_IF

error := internalError;
IF internalError THEN
    status := errorStatus;
ELSE
    status := 0;
END_IF

lastAdd := addRecipe;
lastDelete := deleteRecipe;
lastModify := modifyRecipe;
lastQuery := queryRecipe;

END_FUNCTION_BLOCK
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
    addRecipePrev : BOOL := FALSE;
    deleteRecipePrev : BOOL := FALSE;
    modifyRecipePrev : BOOL := FALSE;
    queryRecipePrev : BOOL := FALSE;
    foundIndex : INT;
    i : INT;
    isDuplicate : BOOL;
    isFound : BOOL;
END_VAR

    error := FALSE;
    status := 16#0000;
    recipeAdded := FALSE;
    recipeDeleted := FALSE;
    recipeModified := FALSE;

    IF addRecipe AND NOT addRecipePrev THEN
        isDuplicate := FALSE;
        isFound := FALSE;
        foundIndex := 0;
        
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                isDuplicate := TRUE;
                EXIT;
            END_IF
        END_FOR
        
        IF isDuplicate THEN
            error := TRUE;
            status := 16#8002;
        ELSE
            foundIndex := 0;
            FOR i := 1 TO 10 DO
                IF recipe[i].recipeID = 0 THEN
                    foundIndex := i;
                    EXIT;
                END_IF
            END_FOR
            
            IF foundIndex = 0 THEN
                error := TRUE;
                status := 16#8003;
            ELSE
                recipe[foundIndex] := recipeIn;
                recipeAdded := TRUE;
            END_IF
        END_IF
    END_IF

    IF deleteRecipe AND NOT deleteRecipePrev THEN
        isFound := FALSE;
        foundIndex := 0;
        
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                isFound := TRUE;
                foundIndex := i;
                EXIT;
            END_IF
        END_FOR
        
        IF NOT isFound THEN
            error := TRUE;
            status := 16#8004;
        ELSE
            recipe[foundIndex].recipeID := 0;
            recipeDeleted := TRUE;
        END_IF
    END_IF

    IF modifyRecipe AND NOT modifyRecipePrev THEN
        isFound := FALSE;
        foundIndex := 0;
        
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                isFound := TRUE;
                foundIndex := i;
                EXIT;
            END_IF
        END_FOR
        
        IF NOT isFound THEN
            error := TRUE;
            status := 16#8005;
        ELSE
            recipe[foundIndex] := recipeIn;
            recipeModified := TRUE;
        END_IF
    END_IF

    IF queryRecipe AND NOT queryRecipePrev THEN
        isFound := FALSE;
        foundIndex := 0;
        
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                isFound := TRUE;
                foundIndex := i;
                EXIT;
            END_IF
        END_FOR
        
        IF NOT isFound THEN
            error := TRUE;
            status := 16#8001;
        ELSE
            recipeQueryResult := recipe[foundIndex];
        END_IF
    END_IF

    addRecipePrev := addRecipe;
    deleteRecipePrev := deleteRecipe;
    modifyRecipePrev := modifyRecipe;
    queryRecipePrev := queryRecipe;

END_FUNCTION_BLOCK
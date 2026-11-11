FUNCTION_BLOCK RecipeManagement
VAR_INPUT
    addRecipe    : BOOL;
    deleteRecipe : BOOL;
    modifyRecipe : BOOL;
    queryRecipe  : BOOL;
    recipeIn     : ST_Recipe;
END_VAR

VAR_OUTPUT
    recipeAdded       : BOOL;
    recipeDeleted     : BOOL;
    recipeModified    : BOOL;
    recipeQueryResult : ST_Recipe;
    error             : BOOL;
    status            : WORD;
END_VAR

VAR_IN_OUT
    recipe : ARRAY[1..10] OF ST_Recipe;
END_VAR

VAR
    i              : INT;
    foundIndex     : INT;
    emptySlotIndex : INT;
    found          : BOOL;
END_VAR

//---------------------------------------------------------------------------
// Initialization
//---------------------------------------------------------------------------
error            := FALSE;
status           := 16#0000;
recipeAdded      := FALSE;
recipeDeleted    := FALSE;
recipeModified   := FALSE;
recipeQueryResult.recipeID              := 0;
recipeQueryResult.ingredientType        := 0;
recipeQueryResult.ingredientRatio       := 0.0;
recipeQueryResult.productionTemperature := 0.0;

//---------------------------------------------------------------------------
// Query Recipe Operation
//---------------------------------------------------------------------------
IF queryRecipe THEN
    found      := FALSE;
    foundIndex := 0;
    
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            found      := TRUE;
            foundIndex := i;
            EXIT;
        END_IF
    END_FOR
    
    IF found THEN
        recipeQueryResult := recipe[foundIndex];
        error  := FALSE;
        status := 16#0000;
    ELSE
        error  := TRUE;
        status := 16#8001;
    END_IF
END_IF

//---------------------------------------------------------------------------
// Add Recipe Operation
//---------------------------------------------------------------------------
IF addRecipe THEN
    found      := FALSE;
    foundIndex := 0;
    
    // Check for duplicate recipeID
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            found := TRUE;
            EXIT;
        END_IF
    END_FOR
    
    IF found THEN
        error  := TRUE;
        status := 16#8002;
    ELSE
        // Find first empty slot (smallest index)
        found          := FALSE;
        emptySlotIndex := 0;
        
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID = 0 THEN
                emptySlotIndex := i;
                found          := TRUE;
                EXIT;
            END_IF
        END_FOR
        
        IF NOT found THEN
            error  := TRUE;
            status := 16#8003;
        ELSE
            recipe[emptySlotIndex] := recipeIn;
            recipeAdded            := TRUE;
            error                  := FALSE;
            status                 := 16#0000;
        END_IF
    END_IF
END_IF

//---------------------------------------------------------------------------
// Delete Recipe Operation
//---------------------------------------------------------------------------
IF deleteRecipe THEN
    found      := FALSE;
    foundIndex := 0;
    
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            found      := TRUE;
            foundIndex := i;
            EXIT;
        END_IF
    END_FOR
    
    IF found THEN
        recipe[foundIndex].recipeID              := 0;
        recipe[foundIndex].ingredientType        := 0;
        recipe[foundIndex].ingredientRatio       := 0.0;
        recipe[foundIndex].productionTemperature := 0.0;
        recipeDeleted                            := TRUE;
        error                                    := FALSE;
        status                                   := 16#0000;
    ELSE
        error  := TRUE;
        status := 16#8004;
    END_IF
END_IF

//---------------------------------------------------------------------------
// Modify Recipe Operation
//---------------------------------------------------------------------------
IF modifyRecipe THEN
    found      := FALSE;
    foundIndex := 0;
    
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            found      := TRUE;
            foundIndex := i;
            EXIT;
        END_IF
    END_FOR
    
    IF found THEN
        recipe[foundIndex] := recipeIn;
        recipeModified     := TRUE;
        error              := FALSE;
        status             := 16#0000;
    ELSE
        error  := TRUE;
        status := 16#8005;
    END_IF
END_IF

END_FUNCTION_BLOCK
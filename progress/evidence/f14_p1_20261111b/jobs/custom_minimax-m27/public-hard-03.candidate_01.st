PROGRAM RecipeManagement
VAR
    // Inputs
    addRecipe        : BOOL;
    deleteRecipe     : BOOL;
    modifyRecipe     : BOOL;
    queryRecipe      : BOOL;
    recipeIn         : ST_Recipe;
    
    // Outputs
    recipeAdded          : BOOL;
    recipeDeleted        : BOOL;
    recipeModified       : BOOL;
    recipeQueryResult    : ST_Recipe;
    error            : BOOL;
    status           : WORD;
    
    // Input/Output
    recipe           : ARRAY[1..10] OF ST_Recipe;
    
    // Internal variables
    i               : INT;
    foundIndex      : INT;
    emptySlotIndex  : INT;
    hasDuplicate    : BOOL;
    hasEmptySlot    : BOOL;
    found           : BOOL;
END_VAR

//---------------------------------------------------------------------------
// Initialization - Clear outputs at the start of each cycle
//---------------------------------------------------------------------------
error            := FALSE;
status           := 16#0000;
recipeAdded      := FALSE;
recipeDeleted    := FALSE;
recipeModified   := FALSE;

// Initialize query result to empty recipe
recipeQueryResult.recipeID              := 0;
recipeQueryResult.ingredientType        := 0;
recipeQueryResult.ingredientRatio       := 0.0;
recipeQueryResult.productionTemperature := 0.0;

//---------------------------------------------------------------------------
// Query Recipe Operation
// Triggered when queryRecipe signal is TRUE
// Searches for recipe by recipeID and outputs result
//---------------------------------------------------------------------------
IF queryRecipe THEN
    found      := FALSE;
    foundIndex := 0;
    
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            found      := TRUE;
            foundIndex := i;
            EXIT; // Exit loop once found
        END_IF
    END_FOR
    
    IF found THEN
        // Recipe found - output to query result
        recipeQueryResult := recipe[foundIndex];
        error  := FALSE;
        status := 16#0000;
    ELSE
        // Recipe not found - error status 16#8001
        error  := TRUE;
        status := 16#8001;
    END_IF
END_IF

//---------------------------------------------------------------------------
// Add Recipe Operation
// Triggered when addRecipe signal is TRUE
// Adds new recipe to first available empty slot
//---------------------------------------------------------------------------
IF addRecipe THEN
    hasDuplicate   := FALSE;
    hasEmptySlot   := FALSE;
    emptySlotIndex := 0;
    found          := FALSE;
    foundIndex     := 0;
    
    // Step 1: Check for duplicate recipeID
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            hasDuplicate := TRUE;
            found        := TRUE;
            EXIT;
        END_IF
    END_FOR
    
    IF hasDuplicate THEN
        // Duplicate recipeID found - error status 16#8002
        error  := TRUE;
        status := 16#8002;
    ELSE
        // Step 2: Find first empty slot (smallest index)
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID = 0 THEN
                hasEmptySlot   := TRUE;
                emptySlotIndex := i;
                EXIT;
            END_IF
        END_FOR
        
        IF NOT hasEmptySlot THEN
            // No empty slot available - error status 16#8003
            error  := TRUE;
            status := 16#8003;
        ELSE
            // Step 3: Store recipe in empty slot with smallest index
            recipe[emptySlotIndex] := recipeIn;
            recipeAdded            := TRUE;
            error                  := FALSE;
            status                 := 16#0000;
        END_IF
    END_IF
END_IF

//---------------------------------------------------------------------------
// Delete Recipe Operation
// Triggered when deleteRecipe signal is TRUE
// Sets recipeID to 0 (marks slot as empty)
//---------------------------------------------------------------------------
IF deleteRecipe THEN
    found      := FALSE;
    foundIndex := 0;
    
    // Search for recipe by recipeID
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            found      := TRUE;
            foundIndex := i;
            EXIT;
        END_IF
    END_FOR
    
    IF found THEN
        // Recipe found - delete by setting recipeID to 0
        recipe[foundIndex].recipeID              := 0;
        recipe[foundIndex].ingredientType        := 0;
        recipe[foundIndex].ingredientRatio       := 0.0;
        recipe[foundIndex].productionTemperature := 0.0;
        recipeDeleted                            := TRUE;
        error                                    := FALSE;
        status                                   := 16#0000;
    ELSE
        // Recipe not found - error status 16#8004
        error  := TRUE;
        status := 16#8004;
    END_IF
END_IF

//---------------------------------------------------------------------------
// Modify Recipe Operation
// Triggered when modifyRecipe signal is TRUE
// Replaces existing recipe with input recipe
//---------------------------------------------------------------------------
IF modifyRecipe THEN
    found      := FALSE;
    foundIndex := 0;
    
    // Search for recipe by recipeID
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            found      := TRUE;
            foundIndex := i;
            EXIT;
        END_IF
    END_FOR
    
    IF found THEN
        // Recipe found - replace with input recipe
        recipe[foundIndex] := recipeIn;
        recipeModified     := TRUE;
        error              := FALSE;
        status             := 16#0000;
    ELSE
        // Recipe not found - error status 16#8005
        error  := TRUE;
        status := 16#8005;
    END_IF
END_IF

END_PROGRAM
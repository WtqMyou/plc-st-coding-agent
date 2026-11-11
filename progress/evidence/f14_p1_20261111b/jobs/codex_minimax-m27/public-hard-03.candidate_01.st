PROGRAM RecipeManagement
VAR
    // Inputs
    addRecipe     : BOOL;
    deleteRecipe  : BOOL;
    modifyRecipe  : BOOL;
    queryRecipe   : BOOL;
    recipeIn      : ST_Recipe;
    
    // Outputs
    recipeAdded         : BOOL;
    recipeDeleted       : BOOL;
    recipeModified      : BOOL;
    recipeQueryResult   : ST_Recipe;
    error               : BOOL;
    status              : WORD;
    
    // Internal variables
    recipe              : ARRAY[1..10] OF ST_Recipe;
    i                   : INT;
    foundIndex          : INT;
    emptySlotIndex      : INT;
END_VAR
// Implementation
// Initialize internal tracking variables
foundIndex := 0;
emptySlotIndex := 0;

// Reset all output signals
recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 16#0000;

// Search for existing recipe and find first empty slot
FOR i := 1 TO 10 DO
    IF recipe[i].recipeID <> 0 THEN
        // This slot contains a recipe
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            foundIndex := i;
        END_IF
    ELSE
        // This is an empty slot
        IF emptySlotIndex = 0 THEN
            emptySlotIndex := i;
        END_IF
    END_IF
END_FOR;

// Handle Query Recipe Request
IF queryRecipe THEN
    IF foundIndex <> 0 THEN
        // Recipe found - output it
        recipeQueryResult := recipe[foundIndex];
    ELSE
        // Recipe not found - error
        error := TRUE;
        status := 16#8001;
    END_IF
END_IF

// Handle Add Recipe Request
IF addRecipe THEN
    IF foundIndex <> 0 THEN
        // Duplicate recipe number found - error
        error := TRUE;
        status := 16#8002;
    ELSIF emptySlotIndex = 0 THEN
        // No empty slot available - error
        error := TRUE;
        status := 16#8003;
    ELSE
        // Add recipe to the first empty slot
        recipe[emptySlotIndex] := recipeIn;
        recipeAdded := TRUE;
    END_IF
END_IF

// Handle Delete Recipe Request
IF deleteRecipe THEN
    IF foundIndex <> 0 THEN
        // Recipe found - delete it by setting recipeID to 0
        recipe[foundIndex].recipeID := 0;
        recipeDeleted := TRUE;
    ELSE
        // Recipe not found - error
        error := TRUE;
        status := 16#8004;
    END_IF
END_IF

// Handle Modify Recipe Request
IF modifyRecipe THEN
    IF foundIndex <> 0 THEN
        // Recipe found - replace with input recipe
        recipe[foundIndex] := recipeIn;
        recipeModified := TRUE;
    ELSE
        // Recipe not found - error
        error := TRUE;
        status := 16#8005;
    END_IF
END_IF
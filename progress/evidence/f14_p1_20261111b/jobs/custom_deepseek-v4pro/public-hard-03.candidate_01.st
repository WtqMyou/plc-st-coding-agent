FUNCTION_BLOCK RecipeManagementFB
VAR_INPUT
    addRecipe : BOOL;                    // Add Recipe Request Signal
    deleteRecipe : BOOL;                 // Delete Recipe Request Signal
    modifyRecipe : BOOL;                 // Modify Recipe Request Signal
    queryRecipe : BOOL;                  // Query Recipe Request Signal
    recipeIn : ST_Recipe;                // Input Recipe
END_VAR
VAR_OUTPUT
    recipeAdded : BOOL;                  // Recipe Added Success Indicator
    recipeDeleted : BOOL;                // Recipe Deleted Success Indicator
    recipeModified : BOOL;               // Recipe Modified Success Indicator
    recipeQueryResult : ST_Recipe;       // Recipe Query Result Output
    error : BOOL;                        // Error Status Indicator
    status : WORD;                       // Status Code
END_VAR
VAR_IN_OUT
    recipe : ARRAY[1..10] OF ST_Recipe;  // Recipe Database
END_VAR
VAR
    lastAdd : BOOL := FALSE;             // Previous scan add signal
    lastDelete : BOOL := FALSE;          // Previous scan delete signal
    lastModify : BOOL := FALSE;          // Previous scan modify signal
    lastQuery : BOOL := FALSE;           // Previous scan query signal
    i : INT;                             // Loop counter
    foundIdx : INT;                      // Found index in array
    isDuplicate : BOOL;                  // Duplicate recipe flag
END_VAR

// Main execution starts here:
// Reset success indicators and error/status at the beginning of each scan
recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 0;

// Process one request per scan based on rising edge detection
// Priority order: Add, Delete, Modify, Query (first detected wins)
IF addRecipe AND NOT lastAdd THEN
    // ------------------------------------------------------------
    // Add Recipe Request
    // ------------------------------------------------------------
    // Check for duplicate recipeID
    isDuplicate := FALSE;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            isDuplicate := TRUE;
            EXIT;
        END_IF;
    END_FOR;

    IF isDuplicate THEN
        // Duplicate number found -> error
        error := TRUE;
        status := 16#8002;
    ELSE
        // No duplicate: find first empty slot (recipeID = 0)
        foundIdx := 0;
        FOR i := 1 TO 10 DO
            IF recipe[i].recipeID = 0 THEN
                foundIdx := i;
                EXIT;
            END_IF;
        END_FOR;

        IF foundIdx = 0 THEN
            // No empty slot available -> error
            error := TRUE;
            status := 16#8003;
        ELSE
            // Success: store recipeIn into the first empty slot
            recipe[foundIdx] := recipeIn;
            recipeAdded := TRUE;
        END_IF;
    END_IF;

ELSIF deleteRecipe AND NOT lastDelete THEN
    // ------------------------------------------------------------
    // Delete Recipe Request
    // ------------------------------------------------------------
    foundIdx := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            foundIdx := i;
            EXIT;
        END_IF;
    END_FOR;

    IF foundIdx = 0 THEN
        // Recipe not found -> error
        error := TRUE;
        status := 16#8004;
    ELSE
        // Success: mark slot as empty by setting recipeID to 0
        recipe[foundIdx].recipeID := 0;
        recipeDeleted := TRUE;
    END_IF;

ELSIF modifyRecipe AND NOT lastModify THEN
    // ------------------------------------------------------------
    // Modify Recipe Request
    // ------------------------------------------------------------
    foundIdx := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            foundIdx := i;
            EXIT;
        END_IF;
    END_FOR;

    IF foundIdx = 0 THEN
        // Recipe not found -> error
        error := TRUE;
        status := 16#8005;
    ELSE
        // Success: replace the existing recipe with input recipe
        recipe[foundIdx] := recipeIn;
        recipeModified := TRUE;
    END_IF;

ELSIF queryRecipe AND NOT lastQuery THEN
    // ------------------------------------------------------------
    // Query Recipe Request
    // ------------------------------------------------------------
    foundIdx := 0;
    FOR i := 1 TO 10 DO
        IF recipe[i].recipeID = recipeIn.recipeID THEN
            foundIdx := i;
            EXIT;
        END_IF;
    END_FOR;

    IF foundIdx = 0 THEN
        // Recipe not found -> error
        error := TRUE;
        status := 16#8001;
    ELSE
        // Success: output the found recipe
        recipeQueryResult := recipe[foundIdx];
    END_IF;
END_IF;

// Update edge detection memory for next scan
lastAdd := addRecipe;
lastDelete := deleteRecipe;
lastModify := modifyRecipe;
lastQuery := queryRecipe;

END_FUNCTION_BLOCK
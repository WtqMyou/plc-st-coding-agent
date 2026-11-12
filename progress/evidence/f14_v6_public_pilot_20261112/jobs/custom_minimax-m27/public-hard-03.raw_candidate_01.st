(* ENGINEERING_CONTRACT
| Output/State      | Activation          | Retention     | Reset               | Same-scan Priority | Units/Boundaries              |
|-------------------|---------------------|---------------|---------------------|--------------------|-------------------------------|
| recipeAdded       | addRecipe success   | Latched       | Implicit next call  | True               | status=16#0000 on success     |
| recipeDeleted     | deleteRecipe success| Latched       | Implicit next call  | True               | status=16#0000 on success     |
| recipeModified    | modifyRecipe success| Latched       | Implicit next call  | True               | status=16#0000 on success     |
| recipeQueryResult | queryRecipe found   | Held          | Implicit next call  | True               | Populated on match; preserved |
| error             | Any error condition | Latched       | Implicit next call  | True               | 16#8001-16#8005               |
| status            | Any operation       | Held          | Implicit next call  | True               | Error code or 0               |

Operation Order (same-scan priority): addRecipe > deleteRecipe > modifyRecipe > queryRecipe
Empty slot detection: recipeID = 0 in database slot
Duplicate detection: Any database slot with matching non-zero recipeID
Search scope: ARRAY[1..10] OF ST_Recipe, sequential scan
*)
(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB_RecipeManagement
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
    tmp_index     : INT;
    tmp_found     : BOOL;
    tmp_emptySlot : INT;
    tmp_emptyFound: BOOL;
END_VAR

    // Initialize outputs to safe state at start of scan
    recipeAdded  := FALSE;
    recipeDeleted  := FALSE;
    recipeModified := FALSE;
    error          := FALSE;
    status         := 16#0000;

    // Process operations in same-scan priority order: add > delete > modify > query
    // PUB010: Add Recipe
    IF addRecipe THEN
        tmp_found     := FALSE;
        tmp_emptySlot := 0;
        tmp_emptyFound := FALSE;
        tmp_index     := 1;

        // Search for duplicate and empty slot
        FOR tmp_index := 1 TO 10 DO
            IF recipe[tmp_index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                tmp_found := TRUE;
                EXIT;
            END_IF
        END_FOR

        IF NOT tmp_found THEN
            // No duplicate found, search for empty slot
            FOR tmp_index := 1 TO 10 DO
                IF recipe[tmp_index].recipeID = 0 THEN
                    tmp_emptySlot := tmp_index;
                    tmp_emptyFound := TRUE;
                    EXIT;
                END_IF
            END_FOR
        END_IF

        IF tmp_found THEN
            // Duplicate recipe number exists
            // PUB010: error code 16#8002
            error  := TRUE;
            status := 16#8002;
        ELSIF NOT tmp_emptyFound THEN
            // No empty slot available
            // PUB010: error code 16#8003
            error  := TRUE;
            status := 16#8003;
        ELSE
            // Store in smallest index empty slot
            recipe[tmp_emptySlot] := recipeIn;
            recipeAdded := TRUE;
            error       := FALSE;
            status      := 16#0000;
        END_IF
        RETURN;
    END_IF

    // PUB011: Delete Recipe
    IF deleteRecipe THEN
        tmp_found := FALSE;
        tmp_index := 1;

        // Search for matching recipe number
        FOR tmp_index := 1 TO 10 DO
            IF recipe[tmp_index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                tmp_found := TRUE;
                EXIT;
            END_IF
        END_FOR

        IF NOT tmp_found THEN
            // Recipe number does not exist
            // PUB011: error code 16#8004
            error  := TRUE;
            status := 16#8004;
        ELSE
            // Delete recipe by setting recipeID to 0
            recipe[tmp_index].recipeID := 0;
            recipeDeleted := TRUE;
            error         := FALSE;
            status        := 16#0000;
        END_IF
        RETURN;
    END_IF

    // PUB012: Modify Recipe
    IF modifyRecipe THEN
        tmp_found := FALSE;
        tmp_index := 1;

        // Search for matching recipe number
        FOR tmp_index := 1 TO 10 DO
            IF recipe[tmp_index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                tmp_found := TRUE;
                EXIT;
            END_IF
        END_FOR

        IF NOT tmp_found THEN
            // Recipe number does not exist
            // PUB012: error code 16#8005
            error  := TRUE;
            status := 16#8005;
        ELSE
            // Replace recipe with input recipe
            recipe[tmp_index] := recipeIn;
            recipeModified := TRUE;
            error          := FALSE;
            status         := 16#0000;
        END_IF
        RETURN;
    END_IF

    // PUB009: Query Recipe
    IF queryRecipe THEN
        tmp_found := FALSE;
        tmp_index := 1;

        // Search for matching recipe number
        FOR tmp_index := 1 TO 10 DO
            IF recipe[tmp_index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                tmp_found := TRUE;
                recipeQueryResult := recipe[tmp_index];
                EXIT;
            END_IF
        END_FOR

        IF NOT tmp_found THEN
            // Recipe number does not exist
            // PUB009: error code 16#8001
            error  := TRUE;
            status := 16#8001;
        ELSE
            error  := FALSE;
            status := 16#0000;
        END_IF
        RETURN;
    END_IF

END_FUNCTION_BLOCK
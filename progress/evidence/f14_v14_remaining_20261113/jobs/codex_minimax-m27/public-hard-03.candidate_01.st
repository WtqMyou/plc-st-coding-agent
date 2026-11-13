(* ENGINEERING_CONTRACT *)
(*
  Operation Priority (PUB001): Sequential evaluation order
    1. QUERY   - Read-only, sets recipeQueryResult
    2. ADD     - Write to empty slot, sets recipeAdded
    3. DELETE  - Write-clear slot, sets recipeDeleted  
    4. MODIFY  - Write-replace slot, sets recipeModified
  
  Activation  : Edge-triggered via R_TRIG on command inputs
  Retention   : All outputs (except recipeQueryResult) are single-scan pulses
  Reset       : Outputs clear on subsequent scans when command deasserted
  Same-scan   : Final command state determines which R_TRIG fires
  Error       : error=TRUE with status code, no data written
  Success     : Specific success flag TRUE, error=FALSE, status=0
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK RecipeManagement
VAR_INPUT
    addRecipe    : BOOL;
    deleteRecipe : BOOL;
    modifyRecipe : BOOL;
    queryRecipe  : BOOL;
    recipeIn     : ST_Recipe;
END_VAR

VAR_OUTPUT
    recipeAdded       : BOOL := FALSE;
    recipeDeleted     : BOOL := FALSE;
    recipeModified    : BOOL := FALSE;
    recipeQueryResult : ST_Recipe;
    error             : BOOL := FALSE;
    status            : WORD := 0;
END_VAR

VAR_IN_OUT
    recipe : ARRAY[1..10] OF ST_Recipe;
END_VAR

VAR
    trigAdd    : R_TRIG;
    trigDelete : R_TRIG;
    trigModify : R_TRIG;
    trigQuery  : R_TRIG;
    tmp_i      : INT;
    tmp_slot   : INT;
    tmp_found  : BOOL;
    tmp_empty  : BOOL;
END_VAR

// Clear output flags at start of each scan
recipeAdded    := FALSE;
recipeDeleted  := FALSE;
recipeModified := FALSE;
error          := FALSE;
status         := 0;

// Detect rising edges on command inputs
trigQuery(IN:=queryRecipe);
trigAdd(IN:=addRecipe);
trigDelete(IN:=deleteRecipe);
trigModify(IN:=modifyRecipe);

// Operation 1: Query Recipe (PUB002, PUB008)
IF trigQuery.Q THEN
    tmp_found := FALSE;
    tmp_i := 1;
    WHILE tmp_i <= 10 AND NOT tmp_found DO
        IF recipe[tmp_i].recipeID = recipeIn.recipeID THEN
            tmp_found := TRUE;
        ELSE
            tmp_i := tmp_i + 1;
        END_IF;
    END_WHILE;
    
    IF tmp_found THEN
        recipeQueryResult := recipe[tmp_i];
        error   := FALSE;
        status  := 0;
    ELSE
        error   := TRUE;
        status  := 16#8001;  // Recipe not found
    END_IF;
END_IF;

// Operation 2: Add Recipe (PUB003, PUB009)
IF trigAdd.Q THEN
    // Check for duplicate recipeID
    tmp_found := FALSE;
    tmp_i := 1;
    WHILE tmp_i <= 10 AND NOT tmp_found DO
        IF recipe[tmp_i].recipeID = recipeIn.recipeID THEN
            tmp_found := TRUE;
        ELSE
            tmp_i := tmp_i + 1;
        END_IF;
    END_WHILE;
    
    IF tmp_found THEN
        error   := TRUE;
        status  := 16#8002;  // Duplicate recipeID
    ELSE
        // Find first empty slot (smallest index)
        tmp_empty := FALSE;
        tmp_slot  := 1;
        WHILE tmp_slot <= 10 AND NOT tmp_empty DO
            IF recipe[tmp_slot].recipeID = 0 THEN
                tmp_empty := TRUE;
            ELSE
                tmp_slot := tmp_slot + 1;
            END_IF;
        END_WHILE;
        
        IF tmp_empty THEN
            recipe[tmp_slot] := recipeIn;
            recipeAdded := TRUE;
            error       := FALSE;
            status      := 0;
        ELSE
            error   := TRUE;
            status  := 16#8003;  // No empty slot
        END_IF;
    END_IF;
END_IF;

// Operation 3: Delete Recipe (PUB004, PUB010)
IF trigDelete.Q THEN
    tmp_found := FALSE;
    tmp_i := 1;
    WHILE tmp_i <= 10 AND NOT tmp_found DO
        IF recipe[tmp_i].recipeID = recipeIn.recipeID THEN
            tmp_found := TRUE;
        ELSE
            tmp_i := tmp_i + 1;
        END_IF;
    END_WHILE;
    
    IF tmp_found THEN
        recipe[tmp_i].recipeID         := 0;
        recipe[tmp_i].ingredientType   := 0;
        recipe[tmp_i].ingredientRatio  := 0.0;
        recipe[tmp_i].productionTemperature := 0.0;
        recipeDeleted := TRUE;
        error         := FALSE;
        status        := 0;
    ELSE
        error   := TRUE;
        status  := 16#8004;  // Recipe not found for deletion
    END_IF;
END_IF;

// Operation 4: Modify Recipe (PUB005, PUB011)
IF trigModify.Q THEN
    tmp_found := FALSE;
    tmp_i := 1;
    WHILE tmp_i <= 10 AND NOT tmp_found DO
        IF recipe[tmp_i].recipeID = recipeIn.recipeID THEN
            tmp_found := TRUE;
        ELSE
            tmp_i := tmp_i + 1;
        END_IF;
    END_WHILE;
    
    IF tmp_found THEN
        recipe[tmp_i] := recipeIn;
        recipeModified := TRUE;
        error          := FALSE;
        status         := 0;
    ELSE
        error   := TRUE;
        status  := 16#8005;  // Recipe not found for modification
    END_IF;
END_IF;

END_FUNCTION_BLOCK
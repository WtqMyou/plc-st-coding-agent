{+
FUNCTION_BLOCK FB_RecipeManager
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
    error             : BOOL := FALSE;
    status            : WORD := 16#0000;
    recipeQueryResult : ST_Recipe;
END_VAR
VAR_IN_OUT
    recipe : ARRAY[1..10] OF ST_Recipe;
END_VAR
VAR
    tmp_index     : INT;
    tmp_found     : BOOL;
    tmp_emptySlot : INT;
    tmp_hasEmpty  : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   ====================
   Operation Execution (same-scan, sequential priority):
   1. queryRecipe  → PUB008
   2. addRecipe    → PUB009
   3. deleteRecipe → PUB010
   4. modifyRecipe → PUB011

   Outputs - Activation/Retention/Reset:
   - recipeAdded/recipeDeleted/recipeModified: pulse TRUE on success for current scan only
   - error: TRUE when any error occurs; no explicit reset (overwritten next scan)
   - status: 16#0000 no-error, or error code 16#8001-16#8005 per PUB002

   Error Codes (PUB002):
   - 16#8001: queryRecipe - recipeID not found
   - 16#8002: addRecipe   - recipeID already exists (duplicate)
   - 16#8003: addRecipe   - no empty slot (database full)
   - 16#8004: deleteRecipe - recipeID not found
   - 16#8005: modifyRecipe - recipeID not found

   Database Semantics (PUB006, PUB007):
   - Array index range: [1..10], fixed
   - Empty slot: recipeID = 0
   - Add stores at smallest index empty slot
   - Delete sets recipeID to 0 (marks slot empty)
   - Duplicate recipeID prohibited
*)

(* CONTRACT_RULES [] *)

recipeAdded    := FALSE;
recipeDeleted  := FALSE;
recipeModified := FALSE;
error          := FALSE;
status         := 16#0000;

IF queryRecipe THEN
    tmp_found := FALSE;
    tmp_index := 1;
    WHILE tmp_index <= 10 AND NOT tmp_found DO
        IF recipe[tmp_index].recipeID = recipeIn.recipeID THEN
            tmp_found := TRUE;
        ELSE
            tmp_index := tmp_index + 1;
        END_IF;
    END_WHILE;
    
    IF tmp_found THEN
        recipeQueryResult := recipe[tmp_index];
    ELSE
        error  := TRUE;
        status := 16#8001;
    END_IF;
END_IF;

IF addRecipe THEN
    tmp_found     := FALSE;
    tmp_hasEmpty  := FALSE;
    tmp_emptySlot := 0;
    tmp_index     := 1;
    
    WHILE tmp_index <= 10 DO
        IF recipe[tmp_index].recipeID = recipeIn.recipeID THEN
            tmp_found := TRUE;
            tmp_index := 11;
        ELSE
            IF recipe[tmp_index].recipeID = 0 AND NOT tmp_hasEmpty THEN
                tmp_hasEmpty  := TRUE;
                tmp_emptySlot := tmp_index;
            END_IF;
            tmp_index := tmp_index + 1;
        END_IF;
    END_WHILE;
    
    IF tmp_found THEN
        error  := TRUE;
        status := 16#8002;
    ELSIF NOT tmp_hasEmpty THEN
        error  := TRUE;
        status := 16#8003;
    ELSE
        recipe[tmp_emptySlot] := recipeIn;
        recipeAdded           := TRUE;
    END_IF;
END_IF;

IF deleteRecipe THEN
    tmp_found := FALSE;
    tmp_index := 1;
    
    WHILE tmp_index <= 10 AND NOT tmp_found DO
        IF recipe[tmp_index].recipeID = recipeIn.recipeID THEN
            tmp_found := TRUE;
        ELSE
            tmp_index := tmp_index + 1;
        END_IF;
    END_WHILE;
    
    IF tmp_found THEN
        recipe[tmp_index].recipeID := 0;
        recipeDeleted              := TRUE;
    ELSE
        error  := TRUE;
        status := 16#8004;
    END_IF;
END_IF;

IF modifyRecipe THEN
    tmp_found := FALSE;
    tmp_index := 1;
    
    WHILE tmp_index <= 10 AND NOT tmp_found DO
        IF recipe[tmp_index].recipeID = recipeIn.recipeID THEN
            tmp_found := TRUE;
        ELSE
            tmp_index := tmp_index + 1;
        END_IF;
    END_WHILE;
    
    IF tmp_found THEN
        recipe[tmp_index] := recipeIn;
        recipeModified    := TRUE;
    ELSE
        error  := TRUE;
        status := 16#8005;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
}
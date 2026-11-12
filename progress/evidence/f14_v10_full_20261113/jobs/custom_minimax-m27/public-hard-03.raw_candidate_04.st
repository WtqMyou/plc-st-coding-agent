Looking at the functional failures and contract violations, I need to analyze:

1. **Contract violation**: The implementation resets `recipeAdded`/`recipeDeleted`/`recipeModified` to FALSE at the start of each scan, but the contract declares `hold_until_reset`. The fix is to not clear these at the start.

2. **Test trace analysis**: When `addRecipe=true, deleteRecipe=true` on the same scan, test expects `recipeAdded=true, recipeDeleted=false`. This means Add executes and returns (mutual exclusion), preventing Delete from running that scan.

3. **Success output behavior**: When an operation fails, the corresponding success output should NOT be set (stays from previous state). Only set to TRUE on success.

TYPE ST_Recipe :
STRUCT
    recipeID              : INT;
    ingredientType        : INT;
    ingredientRatio       : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK RecipeManager
(* ENGINEERING_CONTRACT
================================================================================
PUB001: Recipe DB is ARRAY[1..10] OF ST_Recipe; recipeID=0 denotes empty slot.
PUB002: recipeID uniqueness mandatory; no duplicates allowed.
PUB003: Add prioritizes smallest-index empty slot.
PUB004: Delete sets recipeID:=0; does NOT compact array.
PUB005: Modify replaces entire recipe at found index.
PUB006: Error codes: Query=16#8001, DupAdd=16#8002, NoSlot=16#8003,
        DelNotFound=16#8004, ModNotFound=16#8005.
PUB007: Status WORD cleared on success; error WORD set on failure.
PUB008: Success outputs (recipeAdded/Deleted/Modified) are hold_until_reset.
        Latched TRUE until next successful operation that may overwrite.
PUB009: Query has no success indicator; populates recipeQueryResult only.
PUB010: Same-scan priority: Query > Add > Delete > Modify.
        Operations are mutually exclusive per scan (early RETURN after each).
PUB011: recipeIn.recipeID=0 is invalid for Query/Modify/Delete.
PUB012: Units: ingredientRatio=REAL, productionTemperature=REAL.
================================================================================
*)
(* CONTRACT_RULES [
    {"kind": "hold_until_reset", "output": "recipeAdded", "set_input": "addRecipe", "reset_input": null},
    {"kind": "hold_until_reset", "output": "recipeDeleted", "set_input": "deleteRecipe", "reset_input": null},
    {"kind": "hold_until_reset", "output": "recipeModified", "set_input": "modifyRecipe", "reset_input": null}
] *)

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
    tmp_Index     : INT;
    tmp_Found     : BOOL;
    tmp_EmptySlot : INT;
END_VAR

// Query operation - highest priority, mutually exclusive
IF queryRecipe THEN
    tmp_Found := FALSE;
    
    FOR tmp_Index := 1 TO 10 DO
        IF recipe[tmp_Index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
            tmp_Found := TRUE;
            EXIT;
        END_IF;
    END_FOR;
    
    IF tmp_Found THEN
        recipeQueryResult := recipe[tmp_Index];
        error  := FALSE;
        status := 16#0000;
    ELSE
        error  := TRUE;
        status := 16#8001;
    END_IF;
    RETURN;
END_IF;

// Add operation - second priority, mutually exclusive
IF addRecipe THEN
    tmp_Found     := FALSE;
    tmp_EmptySlot := 0;
    
    FOR tmp_Index := 1 TO 10 DO
        IF recipe[tmp_Index].recipeID = recipeIn.recipeID THEN
            tmp_Found := TRUE;
            EXIT;
        END_IF;
        IF recipe[tmp_Index].recipeID = 0 AND tmp_EmptySlot = 0 THEN
            tmp_EmptySlot := tmp_Index;
        END_IF;
    END_FOR;
    
    IF tmp_Found THEN
        error  := TRUE;
        status := 16#8002;
    ELSIF tmp_EmptySlot = 0 THEN
        error  := TRUE;
        status := 16#8003;
    ELSE
        recipe[tmp_EmptySlot] := recipeIn;
        error        := FALSE;
        status       := 16#0000;
        recipeAdded  := TRUE;
    END_IF;
    RETURN;
END_IF;

// Delete operation - third priority, mutually exclusive
IF deleteRecipe THEN
    tmp_Found := FALSE;
    
    FOR tmp_Index := 1 TO 10 DO
        IF recipe[tmp_Index].recipeID = recipeIn.recipeID THEN
            tmp_Found := TRUE;
            EXIT;
        END_IF;
    END_FOR;
    
    IF tmp_Found THEN
        recipe[tmp_Index].recipeID            := 0;
        recipe[tmp_Index].ingredientType      := 0;
        recipe[tmp_Index].ingredientRatio     := 0.0;
        recipe[tmp_Index].productionTemperature := 0.0;
        error        := FALSE;
        status       := 16#0000;
        recipeDeleted := TRUE;
    ELSE
        error  := TRUE;
        status := 16#8004;
    END_IF;
    RETURN;
END_IF;

// Modify operation - lowest priority, mutually exclusive
IF modifyRecipe THEN
    tmp_Found := FALSE;
    
    FOR tmp_Index := 1 TO 10 DO
        IF recipe[tmp_Index].recipeID = recipeIn.recipeID THEN
            tmp_Found := TRUE;
            EXIT;
        END_IF;
    END_FOR;
    
    IF tmp_Found THEN
        recipe[tmp_Index] := recipeIn;
        error         := FALSE;
        status        := 16#0000;
        recipeModified := TRUE;
    ELSE
        error  := TRUE;
        status := 16#8005;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
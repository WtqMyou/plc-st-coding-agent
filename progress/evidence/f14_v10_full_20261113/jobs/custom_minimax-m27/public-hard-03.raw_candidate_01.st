TYPE ST_Recipe :
STRUCT
    recipeID            : INT;
    ingredientType      : INT;
    ingredientRatio     : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE

FUNCTION_BLOCK RecipeManager
(*
ENGINEERING_CONTRACT
================================================================================
PUB001: Recipe DB is ARRAY[1..10] OF ST_Recipe; recipeID=0 denotes empty slot.
PUB002: recipeID uniqueness is mandatory; no duplicates allowed in DB.
PUB003: Add prioritizes smallest-index empty slot.
PUB004: Delete sets recipeID:=0 (soft delete); does NOT compact array.
PUB005: Modify replaces entire recipe at found index by recipeID.
PUB006: Error codes: Query=16#8001, DupAdd=16#8002, NoSlot=16#8003,
        DelNotFound=16#8004, ModNotFound=16#8005.
PUB007: Status WORD cleared to 16#0000 on success; error WORD on failure.
PUB008: Success outputs (recipeAdded/Deleted/Modified) are hold_until_reset.
        No explicit reset input; latched TRUE until next successful operation.
PUB009: Query has no success indicator; only populates recipeQueryResult.
PUB010: All operations use same-scan priority: Query > Add > Delete > Modify.
PUB011: recipeIn.recipeID=0 is treated as invalid for Query/Modify/Delete.
PUB012: Units: ingredientRatio=REAL proportion, productionTemperature=REAL deg.
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

// Initialize outputs at start of each scan
recipeAdded       := FALSE;
recipeDeleted     := FALSE;
recipeModified    := FALSE;
recipeQueryResult.recipeID            := 0;
recipeQueryResult.ingredientType      := 0;
recipeQueryResult.ingredientRatio     := 0.0;
recipeQueryResult.productionTemperature := 0.0;
error   := FALSE;
status  := 16#0000;

// Query operation - highest priority, read-only
IF queryRecipe THEN
    tmp_Found  := FALSE;
    tmp_Index  := 1;
    
    FOR tmp_Index := 1 TO 10 DO
        IF recipe[tmp_Index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
            tmp_Found := TRUE;
            EXIT;
        END_IF
    END_FOR
    
    IF tmp_Found THEN
        recipeQueryResult := recipe[tmp_Index];
        error := FALSE;
    ELSE
        error  := TRUE;
        status := 16#8001;
    END_IF
    RETURN;
END_IF

// Add operation
IF addRecipe THEN
    tmp_Found     := FALSE;
    tmp_EmptySlot := 0;
    
    FOR tmp_Index := 1 TO 10 DO
        IF recipe[tmp_Index].recipeID = recipeIn.recipeID THEN
            tmp_Found := TRUE;
            EXIT;
        END_IF
        IF recipe[tmp_Index].recipeID = 0 AND tmp_EmptySlot = 0 THEN
            tmp_EmptySlot := tmp_Index;
        END_IF
    END_FOR
    
    IF tmp_Found THEN
        error  := TRUE;
        status := 16#8002;
    ELSIF tmp_EmptySlot = 0 THEN
        error  := TRUE;
        status := 16#8003;
    ELSE
        recipe[tmp_EmptySlot] := recipeIn;
        recipeAdded := TRUE;
    END_IF
    RETURN;
END_IF

// Delete operation
IF deleteRecipe THEN
    tmp_Found := FALSE;
    
    FOR tmp_Index := 1 TO 10 DO
        IF recipe[tmp_Index].recipeID = recipeIn.recipeID THEN
            tmp_Found := TRUE;
            EXIT;
        END_IF
    END_FOR
    
    IF tmp_Found THEN
        recipe[tmp_Index].recipeID            := 0;
        recipe[tmp_Index].ingredientType      := 0;
        recipe[tmp_Index].ingredientRatio     := 0.0;
        recipe[tmp_Index].productionTemperature := 0.0;
        recipeDeleted := TRUE;
    ELSE
        error  := TRUE;
        status := 16#8004;
    END_IF
    RETURN;
END_IF

// Modify operation
IF modifyRecipe THEN
    tmp_Found := FALSE;
    
    FOR tmp_Index := 1 TO 10 DO
        IF recipe[tmp_Index].recipeID = recipeIn.recipeID THEN
            tmp_Found := TRUE;
            EXIT;
        END_IF
    END_FOR
    
    IF tmp_Found THEN
        recipe[tmp_Index] := recipeIn;
        recipeModified := TRUE;
    ELSE
        error  := TRUE;
        status := 16#8005;
    END_IF
END_IF

END_FUNCTION_BLOCK
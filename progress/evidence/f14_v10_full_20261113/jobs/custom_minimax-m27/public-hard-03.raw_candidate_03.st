TYPE ST_Recipe :
STRUCT
    recipeID            : INT;
    ingredientType      : INT;
    ingredientRatio     : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE;

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
    tmp_Index           : INT;
    tmp_Found           : BOOL;
    tmp_EmptySlot       : INT;
    tmp_Error           : BOOL;
    tmp_Status          : WORD;
    tmp_Added           : BOOL;
    tmp_Deleted         : BOOL;
    tmp_Modified        : BOOL;
END_VAR

// Initialize error state each scan
tmp_Error    := FALSE;
tmp_Status   := 16#0000;
tmp_Added    := FALSE;
tmp_Deleted  := FALSE;
tmp_Modified := FALSE;

// Clear query result at start of scan
recipeQueryResult.recipeID              := 0;
recipeQueryResult.ingredientType        := 0;
recipeQueryResult.ingredientRatio       := 0.0;
recipeQueryResult.productionTemperature := 0.0;

// Query operation - highest priority
IF queryRecipe THEN
    tmp_Found  := FALSE;
    tmp_Index  := 1;
    
    FOR tmp_Index := 1 TO 10 DO
        IF recipe[tmp_Index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
            tmp_Found := TRUE;
            EXIT;
        END_IF;
    END_FOR;
    
    IF tmp_Found THEN
        recipeQueryResult := recipe[tmp_Index];
    ELSE
        tmp_Error  := TRUE;
        tmp_Status := 16#8001;
    END_IF;
ELSE
    // Add operation
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
            tmp_Error  := TRUE;
            tmp_Status := 16#8002;
        ELSIF tmp_EmptySlot = 0 THEN
            tmp_Error  := TRUE;
            tmp_Status := 16#8003;
        ELSE
            recipe[tmp_EmptySlot] := recipeIn;
            tmp_Added := TRUE;
        END_IF;
    ELSE
        // Delete operation
        IF deleteRecipe THEN
            tmp_Found := FALSE;
            
            FOR tmp_Index := 1 TO 10 DO
                IF recipe[tmp_Index].recipeID = recipeIn.recipeID THEN
                    tmp_Found := TRUE;
                    EXIT;
                END_IF;
            END_FOR;
            
            IF tmp_Found THEN
                recipe[tmp_Index].recipeID              := 0;
                recipe[tmp_Index].ingredientType        := 0;
                recipe[tmp_Index].ingredientRatio       := 0.0;
                recipe[tmp_Index].productionTemperature := 0.0;
                tmp_Deleted := TRUE;
            ELSE
                tmp_Error  := TRUE;
                tmp_Status := 16#8004;
            END_IF;
        ELSE
            // Modify operation
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
                    tmp_Modified := TRUE;
                ELSE
                    tmp_Error  := TRUE;
                    tmp_Status := 16#8005;
                END_IF;
            END_IF;
        END_IF;
    END_IF;
END_IF;

// Update latching outputs (hold_until_reset semantics)
IF tmp_Added THEN
    recipeAdded       := TRUE;
    recipeDeleted     := FALSE;
    recipeModified    := FALSE;
END_IF;

IF tmp_Deleted THEN
    recipeAdded       := FALSE;
    recipeDeleted     := TRUE;
    recipeModified    := FALSE;
END_IF;

IF tmp_Modified THEN
    recipeAdded       := FALSE;
    recipeDeleted     := FALSE;
    recipeModified    := TRUE;
END_IF;

// Update error outputs
error  := tmp_Error;
status := tmp_Status;

END_FUNCTION_BLOCK
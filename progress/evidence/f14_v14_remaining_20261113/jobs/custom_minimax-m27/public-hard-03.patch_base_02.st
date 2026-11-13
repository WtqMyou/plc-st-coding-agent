FUNCTION_BLOCK FB_RecipeManager
VAR_INPUT
    addRecipe      : BOOL;
    deleteRecipe   : BOOL;
    modifyRecipe   : BOOL;
    queryRecipe    : BOOL;
    recipeIn       : ST_Recipe;
END_VAR

VAR_OUTPUT
    recipeAdded        : BOOL;
    recipeDeleted      : BOOL;
    recipeModified     : BOOL;
    recipeQueryResult  : ST_Recipe;
    error              : BOOL;
    status             : WORD;
END_VAR

VAR_IN_OUT
    recipe : ARRAY[1..10] OF ST_Recipe;
END_VAR

VAR
    tmp_foundIndex : INT;
    tmp_emptyIndex : INT;
    tmp_i          : INT;
END_VAR

(*
ENGINEERING_CONTRACT
===================
Operation sequencing (PUB001-PUB005, PUB007-PUB012):
- Commands evaluated in priority order: DELETE > ADD > MODIFY > QUERY when multiple asserted.
- All success pulses are same-scan; no retention across scans.

Query (PUB008):
  Activation:    queryRecipe rising edge or held high during scan.
  Retention:     recipeQueryResult valid until next scan or successful QUERY.
  Reset:         error and status cleared at start of scan.
  Error codes:   16#8001 = recipe not found.
  Units:         Status WORD error code.

Add (PUB009):
  Activation:    addRecipe rising edge or held high.
  Retention:     Stored in smallest-index empty slot; persists until delete.
  Reset:         None (persistent storage).
  Error codes:   16#8002 = duplicate ID; 16#8003 = database full.
  Same-scan:     Duplicate check before empty-slot check.

Delete (PUB010):
  Activation:    deleteRecipe rising edge or held high.
  Retention:     recipeID forced to 0 (empty slot marker).
  Reset:         Implicit (setting ID to 0 removes it).
  Error codes:   16#8004 = recipe not found.

Modify (PUB011-PUB012):
  Activation:    modifyRecipe rising edge or held high.
  Retention:     Full recipe replacement at found slot.
  Reset:         None.
  Error codes:   16#8005 = recipe not found.
*)

(* CONTRACT_RULES [] *)

tmp_foundIndex := 0;
tmp_emptyIndex := 0;
error := FALSE;
status := 16#0;
recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;

IF deleteRecipe THEN
    tmp_foundIndex := 0;
    FOR tmp_i := 1 TO 10 DO
        IF recipe[tmp_i].recipeID <> 0 AND recipe[tmp_i].recipeID = recipeIn.recipeID THEN
            tmp_foundIndex := tmp_i;
            EXIT;
        END_IF;
    END_FOR;

    IF tmp_foundIndex = 0 THEN
        error := TRUE;
        status := 16#8004;
    ELSE
        recipe[tmp_foundIndex].recipeID := 0;
        recipeDeleted := TRUE;
    END_IF;

ELSIF addRecipe THEN
    tmp_foundIndex := 0;
    tmp_emptyIndex := 0;

    FOR tmp_i := 1 TO 10 DO
        IF recipe[tmp_i].recipeID <> 0 AND recipe[tmp_i].recipeID = recipeIn.recipeID THEN
            tmp_foundIndex := tmp_i;
            EXIT;
        END_IF;
    END_FOR;

    IF tmp_foundIndex <> 0 THEN
        error := TRUE;
        status := 16#8002;
    ELSE
        FOR tmp_i := 1 TO 10 DO
            IF recipe[tmp_i].recipeID = 0 AND tmp_emptyIndex = 0 THEN
                tmp_emptyIndex := tmp_i;
                EXIT;
            END_IF;
        END_FOR;

        IF tmp_emptyIndex = 0 THEN
            error := TRUE;
            status := 16#8003;
        ELSE
            recipe[tmp_emptyIndex] := recipeIn;
            recipeAdded := TRUE;
        END_IF;
    END_IF;

ELSIF modifyRecipe THEN
    tmp_foundIndex := 0;
    FOR tmp_i := 1 TO 10 DO
        IF recipe[tmp_i].recipeID <> 0 AND recipe[tmp_i].recipeID = recipeIn.recipeID THEN
            tmp_foundIndex := tmp_i;
            EXIT;
        END_IF;
    END_FOR;

    IF tmp_foundIndex = 0 THEN
        error := TRUE;
        status := 16#8005;
    ELSE
        recipe[tmp_foundIndex] := recipeIn;
        recipeModified := TRUE;
    END_IF;

ELSIF queryRecipe THEN
    tmp_foundIndex := 0;
    FOR tmp_i := 1 TO 10 DO
        IF recipe[tmp_i].recipeID <> 0 AND recipe[tmp_i].recipeID = recipeIn.recipeID THEN
            tmp_foundIndex := tmp_i;
            EXIT;
        END_IF;
    END_FOR;

    IF tmp_foundIndex = 0 THEN
        error := TRUE;
        status := 16#8001;
    ELSE
        recipeQueryResult := recipe[tmp_foundIndex];
    END_IF;
END_IF;

END_FUNCTION_BLOCK
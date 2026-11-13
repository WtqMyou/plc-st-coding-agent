TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    totalRatio : REAL;
    temperature : REAL;
END_STRUCT
END_TYPE;

(* ENGINEERING_CONTRACT
valid: set TRUE only on accepted load edge (loadCmd rising AND NOT running, slot 1..8, recipeID<>0, totalRatio 99..101, temperature 30..180). Set FALSE on accepted invalid edge. Otherwise retains latched value; initial FALSE.
loadedID: set to recipe[selSlot].recipeID on accepted valid edge. Set 0 on accepted invalid edge, including empty/out-of-range/ratio/temp. Retains latched value when no accepted edge or running=TRUE; initial 0.
Priority: running gates loading; no edge processing while running.
Edge: detected once per loadCmd false-to-true scan via local_prevLoadCmd.
Boundaries: inclusive REAL comparisons. Array access only after selSlot 1..8.
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK FB
VAR_INPUT
    recipe : ARRAY[1..8] OF ST_Recipe;
    selSlot : INT;
    loadCmd : BOOL;
    running : BOOL;
END_VAR
VAR_OUTPUT
    valid : BOOL;
    loadedID : INT;
END_VAR
VAR
    local_prevLoadCmd : BOOL := FALSE;
    local_edge : BOOL;
    local_slot : INT;
    local_latchedValid : BOOL := FALSE;
    local_latchedID : INT := 0;
END_VAR

local_edge := loadCmd AND NOT local_prevLoadCmd;
local_prevLoadCmd := loadCmd;

IF local_edge AND NOT running THEN
    local_slot := selSlot;
    IF (local_slot >= 1) AND (local_slot <= 8) THEN
        IF (recipe[local_slot].recipeID <> 0)
           AND (recipe[local_slot].totalRatio >= 99.0)
           AND (recipe[local_slot].totalRatio <= 101.0)
           AND (recipe[local_slot].temperature >= 30.0)
           AND (recipe[local_slot].temperature <= 180.0) THEN
            local_latchedValid := TRUE;
            local_latchedID := recipe[local_slot].recipeID;
        ELSE
            local_latchedValid := FALSE;
            local_latchedID := 0;
        END_IF;
    ELSE
        local_latchedValid := FALSE;
        local_latchedID := 0;
    END_IF;
END_IF;

valid := local_latchedValid;
loadedID := local_latchedID;

END_FUNCTION_BLOCK
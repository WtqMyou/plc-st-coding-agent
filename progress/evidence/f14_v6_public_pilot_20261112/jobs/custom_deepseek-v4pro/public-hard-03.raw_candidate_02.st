(* ENGINEERING_CONTRACT
   Activations: each add/delete/modify/query acted on a rising edge via R_TRIG; no edge -> all operation outputs/error/status cleared (PUB002).
   recipeAdded/recipeDeleted/recipeModified pulse TRUE on one successful edge scan only.
   error/status pulse on same scan as the request edge; status 0 on success or idle; no latch.
   recipeQueryResult zeroed except for successful query (PUB009).
   Simultaneous rising command edges: only the highest-priority command (add > delete > modify > query) is executed; others ignored (unspecified, deterministic).
   Add: duplicate non-zero ID -> 16#8002; no empty slot -> 16#8003; else store at lowest empty index 1..10 (PUB010).
   Delete: not found -> 16#8004; else clear whole slot and set recipeID=0 (PUB011).
   Modify: not found -> 16#8005; else replace whole slot with recipeIn (PUB012).
   Query: not found -> 16#8001; else copy matched non-zero slot to result (PUB009).
   Input recipeID=0 is treated as invalid/absent: add -> 16#8002, delete/modify/query -> not found; empty slots are not considered existing recipes.
*)
(* CONTRACT_RULES [] *)

TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    ingredientType : INT;
    ingredientRatio : REAL;
    productionTemperature : REAL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK FB_RecipeManagement
VAR_INPUT
    addRecipe : BOOL;
    deleteRecipe : BOOL;
    modifyRecipe : BOOL;
    queryRecipe : BOOL;
    recipeIn : ST_Recipe;
END_VAR
VAR_OUTPUT
    recipeAdded : BOOL;
    recipeDeleted : BOOL;
    recipeModified : BOOL;
    recipeQueryResult : ST_Recipe;
    error : BOOL;
    status : WORD;
END_VAR
VAR_IN_OUT
    recipe : ARRAY[1..10] OF ST_Recipe;
END_VAR
VAR
    rtrigAdd : R_TRIG;
    rtrigDelete : R_TRIG;
    rtrigModify : R_TRIG;
    rtrigQuery : R_TRIG;

    local_AddEdge : BOOL;
    local_DeleteEdge : BOOL;
    local_ModifyEdge : BOOL;
    local_QueryEdge : BOOL;
    local_idx : INT;
    local_foundIndex : INT;
    local_emptyIndex : INT;
    local_duplicateFound : BOOL;
END_VAR

rtrigAdd(CLK := addRecipe);
rtrigDelete(CLK := deleteRecipe);
rtrigModify(CLK := modifyRecipe);
rtrigQuery(CLK := queryRecipe);

local_AddEdge := rtrigAdd.Q;
local_DeleteEdge := rtrigDelete.Q;
local_ModifyEdge := rtrigModify.Q;
local_QueryEdge := rtrigQuery.Q;

recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 0;
recipeQueryResult.recipeID := 0;
recipeQueryResult.ingredientType := 0;
recipeQueryResult.ingredientRatio := 0.0;
recipeQueryResult.productionTemperature := 0.0;

IF local_AddEdge THEN
    IF recipeIn.recipeID = 0 THEN
        error := TRUE;
        status := 16#8002;
    ELSE
        local_duplicateFound := FALSE;
        FOR local_idx := 1 TO 10 BY 1 DO
            IF (recipe[local_idx].recipeID <> 0) AND (recipe[local_idx].recipeID = recipeIn.recipeID) THEN
                local_duplicateFound := TRUE;
                EXIT;
            END_IF;
        END_FOR;

        IF local_duplicateFound THEN
            error := TRUE;
            status := 16#8002;
        ELSE
            local_emptyIndex := 0;
            FOR local_idx := 1 TO 10 BY 1 DO
                IF recipe[local_idx].recipeID = 0 THEN
                    local_emptyIndex := local_idx;
                    EXIT;
                END_IF;
            END_FOR;

            IF local_emptyIndex = 0 THEN
                error := TRUE;
                status := 16#8003;
            ELSE
                recipe[local_emptyIndex] := recipeIn;
                recipeAdded := TRUE;
            END_IF;
        END_IF;
    END_IF;

ELSIF local_DeleteEdge THEN
    local_foundIndex := 0;
    FOR local_idx := 1 TO 10 BY 1 DO
        IF (recipe[local_idx].recipeID <> 0) AND (recipe[local_idx].recipeID = recipeIn.recipeID) THEN
            local_foundIndex := local_idx;
            EXIT;
        END_IF;
    END_FOR;

    IF local_foundIndex = 0 THEN
        error := TRUE;
        status := 16#8004;
    ELSE
        recipe[local_foundIndex].recipeID := 0;
        recipe[local_foundIndex].ingredientType := 0;
        recipe[local_foundIndex].ingredientRatio := 0.0;
        recipe[local_foundIndex].productionTemperature := 0.0;
        recipeDeleted := TRUE;
    END_IF;

ELSIF local_ModifyEdge THEN
    local_foundIndex := 0;
    FOR local_idx := 1 TO 10 BY 1 DO
        IF (recipe[local_idx].recipeID <> 0) AND (recipe[local_idx].recipeID = recipeIn.recipeID) THEN
            local_foundIndex := local_idx;
            EXIT;
        END_IF;
    END_FOR;

    IF local_foundIndex = 0 THEN
        error := TRUE;
        status := 16#8005;
    ELSE
        recipe[local_foundIndex] := recipeIn;
        recipeModified := TRUE;
    END_IF;

ELSIF local_QueryEdge THEN
    local_foundIndex := 0;
    FOR local_idx := 1 TO 10 BY 1 DO
        IF (recipe[local_idx].recipeID <> 0) AND (recipe[local_idx].recipeID = recipeIn.recipeID) THEN
            local_foundIndex := local_idx;
            EXIT;
        END_IF;
    END_FOR;

    IF local_foundIndex = 0 THEN
        error := TRUE;
        status := 16#8001;
    ELSE
        recipeQueryResult := recipe[local_foundIndex];
    END_IF;
END_IF;

END_FUNCTION_BLOCK
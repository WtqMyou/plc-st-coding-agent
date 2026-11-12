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
Bounded: status only changes when a command is processed; retained otherwise
*)
(* CONTRACT_RULES [] *)

TYPE ST_Recipe :
STRUCT
    recipeID               : INT;
    ingredientType         : INT;
    ingredientRatio        : REAL;
    productionTemperature  : REAL;
END_STRUCT
END_TYPE;

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
    tmp_index      : INT;
    tmp_found      : BOOL;
    tmp_emptySlot  : INT;
    tmp_emptyFound : BOOL;
END_VAR

    recipeAdded  := FALSE;
    recipeDeleted  := FALSE;
    recipeModified := FALSE;

    IF addRecipe THEN
        tmp_found      := FALSE;
        tmp_emptySlot  := 0;
        tmp_emptyFound := FALSE;
        tmp_index      := 1;

        FOR tmp_index := 1 TO 10 DO
            IF recipe[tmp_index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                tmp_found := TRUE;
                EXIT;
            END_IF;
        END_FOR;

        IF tmp_found THEN
            error  := TRUE;
            status := 16#8002;
        ELSIF NOT tmp_emptyFound THEN
            error  := TRUE;
            status := 16#8003;
        ELSE
            recipe[tmp_emptySlot] := recipeIn;
            recipeAdded := TRUE;
            error       := FALSE;
            status      := 16#0000;
        END_IF;
        RETURN;
    END_IF;

    IF deleteRecipe THEN
        tmp_found := FALSE;
        tmp_index := 1;

        FOR tmp_index := 1 TO 10 DO
            IF recipe[tmp_index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                tmp_found := TRUE;
                EXIT;
            END_IF;
        END_FOR;

        IF NOT tmp_found THEN
            error  := TRUE;
            status := 16#8004;
        ELSE
            recipe[tmp_index].recipeID := 0;
            recipeDeleted := TRUE;
            error         := FALSE;
            status        := 16#0000;
        END_IF;
        RETURN;
    END_IF;

    IF modifyRecipe THEN
        tmp_found := FALSE;
        tmp_index := 1;

        FOR tmp_index := 1 TO 10 DO
            IF recipe[tmp_index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                tmp_found := TRUE;
                EXIT;
            END_IF;
        END_FOR;

        IF NOT tmp_found THEN
            error  := TRUE;
            status := 16#8005;
        ELSE
            recipe[tmp_index] := recipeIn;
            recipeModified := TRUE;
            error          := FALSE;
            status         := 16#0000;
        END_IF;
        RETURN;
    END_IF;

    IF queryRecipe THEN
        tmp_found := FALSE;
        tmp_index := 1;

        FOR tmp_index := 1 TO 10 DO
            IF recipe[tmp_index].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                tmp_found := TRUE;
                recipeQueryResult := recipe[tmp_index];
                status := 16#0000;
                EXIT;
            END_IF;
        END_FOR;

        IF NOT tmp_found THEN
            error  := TRUE;
            status := 16#8001;
        END_IF;
        RETURN;
    END_IF;

END_FUNCTION_BLOCK
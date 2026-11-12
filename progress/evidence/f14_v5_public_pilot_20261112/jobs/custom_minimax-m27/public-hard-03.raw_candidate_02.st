TYPE
    ST_Recipe : STRUCT
        recipeID             : INT;
        ingredientType       : INT;
        ingredientRatio      : REAL;
        productionTemperature: REAL;
    END_STRUCT
END_TYPE

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
    fbAddR    : R_TRIG;
    fbDeleteR : R_TRIG;
    fbModifyR : R_TRIG;
    fbQueryR  : R_TRIG;
    idx       : INT;
    foundIdx  : INT;
    emptyIdx  : INT;
    hasFound  : BOOL;
    hasEmpty  : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
| Output/State       | Activation           | Retention     | Reset/Deactivation           | Same-scan Priority | Units/Boundaries              |
|--------------------|----------------------|---------------|------------------------------|--------------------|-------------------------------|
| recipeAdded        | addRecipe rising edge| FALSE 1 scan  | Auto-clear next scan         | Highest            | BOOL                          |
| recipeDeleted      | deleteRecipe rising  | FALSE 1 scan  | Auto-clear next scan         | Highest            | BOOL                          |
| recipeModified     | modifyRecipe rising  | FALSE 1 scan  | Auto-clear next scan         | Highest            | BOOL                          |
| recipeQueryResult  | queryRecipe success  | Held          | Cleared on next query        | -                  | ST_Recipe                     |
| error              | Any operation fails  | Held          | Cleared on next success      | -                  | BOOL                          |
| status             | Set on error/success | Held          | 16#0000 on success           | -                  | WORD: 16#0000,16#8001-16#8005 |
PUB: PUB001,PUB002,PUB003,PUB004,PUB005,PUB006,PUB008,PUB009,PUB010,PUB011,PUB012
*)
    fbAddR(CLK := addRecipe);
    fbDeleteR(CLK := deleteRecipe);
    fbModifyR(CLK := modifyRecipe);
    fbQueryR(CLK := queryRecipe);

    recipeAdded   := FALSE;
    recipeDeleted := FALSE;
    recipeModified:= FALSE;

    IF fbQueryR.Q THEN
        hasFound := FALSE;
        foundIdx := 0;
        FOR idx := 1 TO 10 DO
            IF recipe[idx].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                hasFound := TRUE;
                foundIdx := idx;
                EXIT;
            END_IF;
        END_FOR;

        IF hasFound THEN
            recipeQueryResult := recipe[foundIdx];
            error  := FALSE;
            status := 16#0000;
        ELSE
            recipeQueryResult.recipeID             := 0;
            recipeQueryResult.ingredientType       := 0;
            recipeQueryResult.ingredientRatio      := 0.0;
            recipeQueryResult.productionTemperature:= 0.0;
            error  := TRUE;
            status := 16#8001;
        END_IF;
    END_IF;

    IF fbAddR.Q THEN
        hasFound := FALSE;
        hasEmpty := FALSE;
        emptyIdx := 0;
        foundIdx := 0;

        FOR idx := 1 TO 10 DO
            IF recipe[idx].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                hasFound := TRUE;
                foundIdx := idx;
                EXIT;
            END_IF;
        END_FOR;

        IF NOT hasFound THEN
            FOR idx := 1 TO 10 DO
                IF recipe[idx].recipeID = 0 THEN
                    hasEmpty := TRUE;
                    emptyIdx := idx;
                    EXIT;
                END_IF;
            END_FOR;
        END_IF;

        IF hasFound THEN
            error  := TRUE;
            status := 16#8002;
        ELSIF NOT hasEmpty THEN
            error  := TRUE;
            status := 16#8003;
        ELSE
            recipe[emptyIdx] := recipeIn;
            recipeAdded      := TRUE;
            error            := FALSE;
            status           := 16#0000;
        END_IF;
    END_IF;

    IF fbDeleteR.Q THEN
        hasFound := FALSE;
        foundIdx := 0;

        FOR idx := 1 TO 10 DO
            IF recipe[idx].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                hasFound := TRUE;
                foundIdx := idx;
                EXIT;
            END_IF;
        END_FOR;

        IF hasFound THEN
            recipe[foundIdx].recipeID := 0;
            recipeDeleted             := TRUE;
            error                     := FALSE;
            status                    := 16#0000;
        ELSE
            error  := TRUE;
            status := 16#8004;
        END_IF;
    END_IF;

    IF fbModifyR.Q THEN
        hasFound := FALSE;
        foundIdx := 0;

        FOR idx := 1 TO 10 DO
            IF recipe[idx].recipeID = recipeIn.recipeID AND recipeIn.recipeID <> 0 THEN
                hasFound := TRUE;
                foundIdx := idx;
                EXIT;
            END_IF;
        END_FOR;

        IF hasFound THEN
            recipe[foundIdx] := recipeIn;
            recipeModified   := TRUE;
            error            := FALSE;
            status           := 16#0000;
        ELSE
            error  := TRUE;
            status := 16#8005;
        END_IF;
    END_IF;
END_FUNCTION_BLOCK
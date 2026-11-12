TYPE ST_Recipe :
STRUCT
    recipeID    : INT;
    totalRatio  : REAL;
    temperature : REAL;
END_STRUCT
END_TYPE;

FUNCTION_BLOCK FB
VAR_INPUT
    recipe   : ARRAY[1..8] OF ST_Recipe;
    selSlot  : INT;
    loadCmd  : BOOL;
    running  : BOOL;
END_VAR
VAR_OUTPUT
    valid    : BOOL;
    loadedID : INT;
END_VAR
VAR
    tmp_prevLoadCmd : BOOL := FALSE;
    tmp_loadRising  : BOOL := FALSE;
    tmp_prevRunning : BOOL := FALSE;
    tmp_prevLoadedID : INT := 0;
    tmp_prevValid   : BOOL := FALSE;
END_VAR

(* ENGINEERING_CONTRACT
 * +----------------------------------------------------+-------------------------------+---------------------------+---------------------------+----------------+
 * | Output/State Group | Activation | Retention/Hold  | Explicit Reset/Deactivation  | Same-Scan Priority        | Units/Boundaries |
 * +--------------------+------------+-----------------+-------------------------------+---------------------------+------------------+
 * | valid              | rising(loadCmd) & !running | Hold across scans unless reset | !running & rising(loadCmd)| Same scan as loadedID | BOOL |
 * | loadedID           | rising(loadCmd) & !running | Hold when running or idle      | !running & rising(loadCmd)| Same scan as valid     | INT[0..recipeID]|
 * | tmp_loadRising     | loadCmd & !tmp_prevLoadCmd | Cleared each scan              | N/A (internal edge detect)| N/A               | BOOL |
 * | tmp_prevLoadCmd    | copy loadCmd each scan      | N/A                            | N/A                       | N/A               | BOOL |
 * | tmp_prevRunning    | copy running each scan      | N/A                            | N/A                       | N/A               | BOOL |
 * +--------------------+------------+-----------------+-------------------------------+---------------------------+------------------+
 *
 * PUB001 (loadCmd rising edge): Only activates on transition FALSE->TRUE
 * PUB002 (selSlot 1..8): Out-of-bounds treated as invalid, no array access
 * PUB003 (validation rules): totalRatio[99.0,101.0], temperature[30.0,180.0], recipeID<>0
 * PUB004 (running=TRUE): Blocks load, preserves loadedID/valid
 * PUB005 (loadedID update): valid->recipe[selSlot].recipeID, invalid->0
 * PUB006 (valid output): TRUE when all 3 conditions met
 * PUB007 (no edge repeat): Rising edge only, not level-sensitive
 *
 * CONTRACT_RULES [{"kind":"hold_until_reset","output":"valid","set_input":"loadCmd","reset_input":null},{"kind":"hold_until_reset","output":"loadedID","set_input":"loadCmd","reset_input":null}]
 *)
tmp_loadRising := loadCmd AND NOT tmp_prevLoadCmd;

IF tmp_prevRunning AND running THEN
    valid := tmp_prevValid;
    loadedID := tmp_prevLoadedID;
ELSIF running THEN
    valid := tmp_prevValid;
    loadedID := tmp_prevLoadedID;
ELSIF tmp_loadRising THEN
    IF (selSlot < 1) OR (selSlot > 8) THEN
        valid := FALSE;
        loadedID := 0;
    ELSIF recipe[selSlot].recipeID = 0 THEN
        valid := FALSE;
        loadedID := 0;
    ELSIF (recipe[selSlot].totalRatio < 99.0) OR (recipe[selSlot].totalRatio > 101.0) THEN
        valid := FALSE;
        loadedID := 0;
    ELSIF (recipe[selSlot].temperature < 30.0) OR (recipe[selSlot].temperature > 180.0) THEN
        valid := FALSE;
        loadedID := 0;
    ELSE
        valid := TRUE;
        loadedID := recipe[selSlot].recipeID;
    END_IF;
ELSE
    valid := tmp_prevValid;
    loadedID := tmp_prevLoadedID;
END_IF;

tmp_prevLoadCmd := loadCmd;
tmp_prevRunning := running;
tmp_prevLoadedID := loadedID;
tmp_prevValid := valid;

END_FUNCTION_BLOCK
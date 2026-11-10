(* 配方结构体必须显式定义：题目给的是 ARRAY[1..8] OF ST_Recipe，
   没有 TYPE 块就读不到字段名，结构体成员访问会被直接判错。 *)
TYPE ST_Recipe :
STRUCT
    recipeID : INT;
    totalRatio : REAL;
    temperature : REAL;
END_STRUCT
END_TYPE

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
    loadPrev : BOOL;
    loadEdge : BOOL;
    ok : BOOL;
    slotOK : BOOL;
    selectedRecipe : ST_Recipe;
END_VAR

loadEdge := loadCmd AND NOT loadPrev;
loadPrev := loadCmd;
(* 生产运行中不接受装载命令：连有效位都不刷新，保持上一次判定 *)
IF loadEdge AND NOT running THEN
    slotOK := (selSlot >= 1) AND (selSlot <= 8);
    (* 关键：先判槽位合法再访问数组。IEC 的 AND 不保证短路，
       所以不能写成 "slotOK AND recipe[selSlot].xxx" 这种依赖短路的写法 *)
    valid := FALSE;
    loadedID := 0;
    IF slotOK THEN
        selectedRecipe := recipe[selSlot];
        ok := selectedRecipe.recipeID <> 0;
        IF selectedRecipe.totalRatio < 99.0 OR selectedRecipe.totalRatio > 101.0 THEN
            ok := FALSE;
        END_IF
        IF selectedRecipe.temperature < 30.0 OR selectedRecipe.temperature > 180.0 THEN
            ok := FALSE;
        END_IF
        valid := ok;
        IF ok THEN
            loadedID := selectedRecipe.recipeID;
        END_IF
    END_IF
END_IF
END_FUNCTION_BLOCK

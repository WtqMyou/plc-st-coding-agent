(*
  Recipe Management System — 参考解（public-hard-03）

  配方库 recipe 是 VAR_IN_OUT 的结构体数组，最多 10 条，recipeID = 0 表示空槽；
  四个请求信号取上升沿，因此一个请求只执行一次（电平保持不会重复执行）。

  需求编号（对应 requirements 的 Notes）：
    R2  查询：号码不存在 -> error=TRUE & status=16#8001；存在 -> 输出到 recipeQueryResult
    R3  新增：号码重复 -> 16#8002；无空槽 -> 16#8003；否则存到下标最小的空槽
    R4  删除：号码不存在 -> 16#8004；存在 -> 把该槽的 recipeID 置 0
    R5  修改：号码不存在 -> 16#8005；存在 -> 用 recipeIn 覆盖该槽
  另有 R1：配方字段 recipeID/ingredientType/ingredientRatio/productionTemperature。

  两处按需求原文做的判定口径（都写在下面的注释里）：
    * 0 号不是合法配方号：查询/删除/修改 0 号一律按"号码不存在"处理；
    * 新增时号码与本库任何一条 recipeID 相同即算重复，因此 0 号会与空槽的 0 相撞，
      在还有空槽时报 16#8002（R3 的判定顺序本来就是"先查重复、再查空槽"）。
*)

TYPE ST_Recipe :
STRUCT
  recipeID : INT;                (* 配方号，0 = 空槽 *)
  ingredientType : INT;          (* 原料类型 *)
  ingredientRatio : REAL;        (* 原料配比 *)
  productionTemperature : REAL;  (* 生产温度 *)
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB
VAR_INPUT
  addRecipe : BOOL;              (* R3 新增请求 *)
  deleteRecipe : BOOL;           (* R4 删除请求 *)
  modifyRecipe : BOOL;           (* R5 修改请求 *)
  queryRecipe : BOOL;            (* R2 查询请求 *)
  recipeIn : ST_Recipe;          (* 请求携带的配方 *)
END_VAR
VAR_OUTPUT
  recipeAdded : BOOL;            (* 新增成功指示，只在执行成功那一拍为 TRUE *)
  recipeDeleted : BOOL;          (* 删除成功指示 *)
  recipeModified : BOOL;         (* 修改成功指示 *)
  recipeQueryResult : ST_Recipe; (* 查询结果，只在查询成功时更新 *)
  error : BOOL;                  (* 出错指示 *)
  status : WORD;                 (* 状态码，0 = 正常 *)
END_VAR
VAR_IN_OUT
  recipe : ARRAY[1..10] OF ST_Recipe;   (* 配方库 *)
END_VAR
VAR
  i : INT;
  hitIdx : INT;                  (* 命中槽，0 = 没命中 *)
  freeIdx : INT;                 (* 下标最小的空槽，0 = 库已满 *)
  dup : BOOL;                    (* 新增时号码重复 *)
  qEdge : BOOL;  qPrev : BOOL;   (* R2 请求上升沿 *)
  aEdge : BOOL;  aPrev : BOOL;   (* R3 *)
  dEdge : BOOL;  dPrev : BOOL;   (* R4 *)
  mEdge : BOOL;  mPrev : BOOL;   (* R5 *)
END_VAR

(* 成功指示与状态码都是"拍"语义：每个周期先清零，只在执行请求的那一拍置位 *)
recipeAdded := FALSE;
recipeDeleted := FALSE;
recipeModified := FALSE;
error := FALSE;
status := 16#0000;

(* 请求信号取上升沿：按钮保持为 TRUE 时不会每个扫描周期都重做一遍 *)
qEdge := queryRecipe AND NOT qPrev;
qPrev := queryRecipe;
aEdge := addRecipe AND NOT aPrev;
aPrev := addRecipe;
dEdge := deleteRecipe AND NOT dPrev;
dPrev := deleteRecipe;
mEdge := modifyRecipe AND NOT mPrev;
mPrev := modifyRecipe;

(* 在库里找 recipeIn 的配方号；0 号是"空槽标记"而不是配方，一律当不存在 *)
hitIdx := 0;
IF recipeIn.recipeID <> 0 THEN
  FOR i := 1 TO 10 DO
    IF (hitIdx = 0) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
      hitIdx := i;
    END_IF
  END_FOR
END_IF

(* 下标最小的空槽，供 R3 的落地位置使用 *)
freeIdx := 0;
FOR i := 1 TO 10 DO
  IF (freeIdx = 0) AND (recipe[i].recipeID = 0) THEN
    freeIdx := i;
  END_IF
END_FOR

(* 四条需求是各自并列的规则：每个请求在自己的上升沿被执行一次，互不吞并 *)
IF qEdge THEN
  (* R2 查询 *)
  IF hitIdx = 0 THEN
    error := TRUE;
    status := 16#8001;
  ELSE
    recipeQueryResult.recipeID := recipe[hitIdx].recipeID;
    recipeQueryResult.ingredientType := recipe[hitIdx].ingredientType;
    recipeQueryResult.ingredientRatio := recipe[hitIdx].ingredientRatio;
    recipeQueryResult.productionTemperature := recipe[hitIdx].productionTemperature;
  END_IF
END_IF

IF aEdge THEN
  (* R3 新增：先查重号，再查空槽 *)
  dup := FALSE;
  FOR i := 1 TO 10 DO
    IF (NOT dup) AND (recipe[i].recipeID = recipeIn.recipeID) THEN
      dup := TRUE;
    END_IF
  END_FOR
  IF dup THEN
    error := TRUE;
    status := 16#8002;
  ELSIF freeIdx = 0 THEN
    error := TRUE;
    status := 16#8003;
  ELSE
    recipe[freeIdx].recipeID := recipeIn.recipeID;
    recipe[freeIdx].ingredientType := recipeIn.ingredientType;
    recipe[freeIdx].ingredientRatio := recipeIn.ingredientRatio;
    recipe[freeIdx].productionTemperature := recipeIn.productionTemperature;
    recipeAdded := TRUE;
  END_IF
END_IF

IF dEdge THEN
  (* R4 删除：只清配方号，槽位立即可以被后续新增复用 *)
  IF hitIdx = 0 THEN
    error := TRUE;
    status := 16#8004;
  ELSE
    recipe[hitIdx].recipeID := 0;
    recipeDeleted := TRUE;
  END_IF
END_IF

IF mEdge THEN
  (* R5 修改：整条配方用 recipeIn 覆盖（结构体不能整体赋值，只能逐字段） *)
  IF hitIdx = 0 THEN
    error := TRUE;
    status := 16#8005;
  ELSE
    recipe[hitIdx].recipeID := recipeIn.recipeID;
    recipe[hitIdx].ingredientType := recipeIn.ingredientType;
    recipe[hitIdx].ingredientRatio := recipeIn.ingredientRatio;
    recipe[hitIdx].productionTemperature := recipeIn.productionTemperature;
    recipeModified := TRUE;
  END_IF
END_IF

END_FUNCTION_BLOCK

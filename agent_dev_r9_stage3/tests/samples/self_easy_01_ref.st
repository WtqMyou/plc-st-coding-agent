FUNCTION_BLOCK FB
VAR_INPUT
    enable : BOOL;
    values : ARRAY[1..8] OF INT;
    count : INT;
    avgEnable : BOOL;
END_VAR
VAR_OUTPUT
    avgOut : REAL;
END_VAR
VAR
    i : INT;
    n : INT;
    sum : DINT;
END_VAR

(* 缓存语义见 Interpreter：输出变量在两次扫描之间保持上一次的值，
   enable / avgEnable / count=0 分支不写 avgOut，就自然"保持上一周期"。 *)

(* 先把有效样本数裁剪到 [0, 8]：count 为负或超过数组长度都不能越界 *)
n := count;
IF n < 0 THEN
    n := 0;
ELSIF n > 8 THEN
    n := 8;
END_IF

(* n = 0 时整段跳过，避免除零；avgOut 保持上一周期的值 *)
IF enable AND avgEnable AND n > 0 THEN
    sum := 0;
    FOR i := 1 TO n DO
        sum := sum + values[i];
    END_FOR
    avgOut := DINT_TO_REAL(sum) / INT_TO_REAL(n);
END_IF
END_FUNCTION_BLOCK

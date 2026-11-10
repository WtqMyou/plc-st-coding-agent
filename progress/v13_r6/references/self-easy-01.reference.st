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
    keep : REAL;
END_VAR

(* 先把有效样本数裁剪到 [0, 8]，负数和超长都收敛到合法范围 *)
n := count;
IF n < 0 THEN
    n := 0;
ELSIF n > 8 THEN
    n := 8;
END_IF

(* 要点：输出变量在每周期扫描开头就被赋成本周期的计算结果，
   "保持不变"没法靠"不写它"实现——必须先读回旧值再决定写不写。
   这里用静态变量 keep 记住上一周期的有效结果。 *)
IF enable AND avgEnable AND n > 0 THEN
    sum := 0;
    FOR i := 1 TO n DO
        sum := sum + values[i];
    END_FOR
    keep := DINT_TO_REAL(sum) / INT_TO_REAL(n);
END_IF
avgOut := keep;
END_FUNCTION_BLOCK

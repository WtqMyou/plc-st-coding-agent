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
    lastAvg : REAL := 0.0;   (* 静态变量，保存上一周期的平均输出 *)
    sum     : DINT;           (* 使用 DINT 累加避免 INT 溢出 *)
    n       : INT;            (* 实际参与计算的样本个数 *)
    i       : INT;            (* 循环变量 *)
END_VAR

    IF enable AND avgEnable AND (count > 0) THEN
        (* 裁剪 count 到最大 8，防止越界访问 *)
        IF count > 8 THEN
            n := 8;
        ELSE
            n := count;
        END_IF;

        (* 使用 DINT 求和，避免 INT 溢出 *)
        sum := 0;
        FOR i := 1 TO n DO
            sum := sum + INT_TO_DINT(values[i]);
        END_FOR;

        avgOut := DINT_TO_REAL(sum) / INT_TO_REAL(n);
    ELSE
        avgOut := lastAvg;    (* 未满足更新条件时保持上一周期输出 *)
    END_IF;

    lastAvg := avgOut;        (* 更新周期末的状态记忆 *)

END_FUNCTION_BLOCK
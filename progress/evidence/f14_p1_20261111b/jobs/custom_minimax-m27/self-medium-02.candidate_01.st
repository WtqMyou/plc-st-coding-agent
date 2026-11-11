FUNCTION_BLOCK FB
VAR_INPUT
    enable    : BOOL;      (* 滤波使能，FALSE 时清空历史 *)
    rawValue  : REAL;      (* 本周期原始采样值 *)
END_VAR

VAR_OUTPUT
    filteredValue : REAL;  (* 滤波输出 *)
    windowFull    : BOOL;  (* 历史窗口已填满 8 个样本后置 TRUE *)
    sampleCount   : INT;   (* 当前窗口内有效样本数 0..8 *)
END_VAR

VAR
    buffer : ARRAY[0..7] OF REAL;  (* 8 点环形缓冲区 *)
    head   : INT := 0;             (* 下一写入位置 0..7 *)
    count  : INT := 0;             (* 有效样本数 0..8 *)
    full   : BOOL := FALSE;        (* 内部满窗标志 *)
END_VAR

VAR_TEMP
    sum : REAL;                    (* 临时累加和 *)
    idx : INT;                     (* 遍历索引 *)
    i   : INT;                     (* 循环计数器 *)
END_VAR

(*--------------------------------------------------------------------*)
(* 功能块主体                                                         *)
(*--------------------------------------------------------------------*)
IF enable THEN
    (* ----- 把新样本压入环形缓冲区 ----- *)
    buffer[head] := rawValue;                 (* 写入 *)
    head := (head + 1) MOD 8;                (* 头指针前移 *)
    IF count < 8 THEN
        count := count + 1;                  (* 样本计数 +1 *)
    END_IF
    full := (count = 8);                     (* 满窗标志 *)

ELSE
    (* ----- enable = FALSE：立即清零计数与满窗标志 ----- *)
    count := 0;
    full  := FALSE;
    (* head 保持不变，下一次 enable=TRUE 时会被覆盖 *)
END_IF

(* ----- 计算滤波输出（仅在有有效样本时） ----- *)
IF enable AND count > 0 THEN
    sum := 0.0;
    (*  oldest  = head - count (模 8) *)
    idx := (head - count + 8) MOD 8;
    FOR i := 0 TO count - 1 DO
        sum := sum + buffer[idx];
        idx := (idx + 1) MOD 8;
    END_FOR
    filteredValue := sum / INT_TO_REAL(count);   (* 算术平均 *)
END_IF
(* 当 enable=FALSE 时 filteredValue 保持不变 *)


(* ----- 输出信号 ----- *)
windowFull  := full;
sampleCount := count;

END_FUNCTION_BLOCK
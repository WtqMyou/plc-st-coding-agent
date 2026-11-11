(* 参考解：Alarm handling（带回差的高/低限报警 + 参数校验）
   报警输出是锁存量：超过限值才置位，回到“限值 ± 回差”以内才复位（回差防抖）。
   参数非法时置 error 并给出 status，且本次扫描不再评估报警（等价于“退出程序”）。 *)
FUNCTION_BLOCK FB_AlarmHandling
VAR_INPUT
    Value : REAL;                   (* 被监视的输入值 *)
    hiLevel : REAL;                 (* 高限报警值 *)
    loLevel : REAL;                 (* 低限报警值 *)
    hystWindow : REAL;              (* 回差窗口 *)
END_VAR
VAR_OUTPUT
    hiAlarm : BOOL;                 (* 高限报警 *)
    loAlarm : BOOL;                 (* 低限报警 *)
    error : BOOL;                   (* 执行出错 *)
    status : WORD;                  (* 状态码：16#8001 / 16#8002 *)
END_VAR

(* R5: 上下限设置反了（loLevel >= hiLevel）-> error，status=16#8001，退出 *)
IF loLevel >= hiLevel THEN
    error := TRUE;
    status := 16#8001;
(* R6: 回差窗口不比正常范围窄（hystWindow >= hiLevel - loLevel）-> error，status=16#8002 *)
ELSIF hystWindow >= (hiLevel - loLevel) THEN
    error := TRUE;
    status := 16#8002;
ELSE
    error := FALSE;
    status := 16#0000;

    (* R1/R2: 高于高限置位；低于 hiLevel-hystWindow 才复位，中间的过渡带保持原状态 *)
    IF Value > hiLevel THEN
        hiAlarm := TRUE;
    ELSIF Value < (hiLevel - hystWindow) THEN
        hiAlarm := FALSE;
    END_IF

    (* R3/R4: 低于低限置位；高于 loLevel+hystWindow 才复位 *)
    IF Value < loLevel THEN
        loAlarm := TRUE;
    ELSIF Value > (loLevel + hystWindow) THEN
        loAlarm := FALSE;
    END_IF
END_IF
END_FUNCTION_BLOCK

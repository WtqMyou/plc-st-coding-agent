(* 参考解：Automated filling line control（清洗 -> 灌装 -> 压盖 -> 包装 -> 完成灯 -> 取瓶复位）
   工序号用内部状态 stepNo 表示：0=空闲 1=清洗 2=灌装 3=压盖 4=包装 5=完成。
   只用接口变量做输出，“工序启动后保持运行”由 stepNo 只增不减保证。 *)
FUNCTION_BLOCK FB_FillingLine
VAR_INPUT
    bottleSensor : BOOL;            (* 瓶子到位检测 *)
    cleaningConfirmButton : BOOL;   (* 清洗完成确认 *)
    fillingConfirmButton : BOOL;    (* 灌装完成确认 *)
    cappingConfirmButton : BOOL;    (* 压盖完成确认 *)
    packingConfirmButton : BOOL;    (* 包装完成确认 *)
    finishedButton : BOOL;          (* 取走瓶子确认 *)
END_VAR
VAR_OUTPUT
    Pump_Motor : BOOL;              (* 清洗泵 *)
    Filling_Valve : BOOL;           (* 灌装阀 *)
    Capping_Machine : BOOL;         (* 压盖机 *)
    Packing_Machine : BOOL;         (* 包装机 *)
    Completion_Light : BOOL;        (* 包装完成指示灯 *)
END_VAR
VAR
    stepNo : INT;                   (* 当前工序号，0=空闲 *)
END_VAR

(* R1: 检测到瓶子就启动清洗泵（stepNo 1），此后 stepNo 不回退，泵持续工作 *)
IF bottleSensor AND (stepNo = 0) THEN
    stepNo := 1;
END_IF

(* R2..R5: 每道工序由“上一道工序完成”的确认按钮推进；只接受当拍工序的确认，
   因此误按后道工序的按钮不会跳步，而且机器一旦启动就保持运行 *)
IF (stepNo = 1) AND cleaningConfirmButton THEN
    stepNo := 2;
ELSIF (stepNo = 2) AND fillingConfirmButton THEN
    stepNo := 3;
ELSIF (stepNo = 3) AND cappingConfirmButton THEN
    stepNo := 4;
ELSIF (stepNo = 4) AND packingConfirmButton THEN
    stepNo := 5;
END_IF

(* R6: 取走瓶子 -> 灭灯并整线复位，准备下一循环 *)
IF finishedButton THEN
    stepNo := 0;
END_IF

(* 各执行机构的输出：由工序号唯一决定，故“启动即保持” *)
Pump_Motor := (stepNo >= 1);
Filling_Valve := (stepNo >= 2);
Capping_Machine := (stepNo >= 3);
Packing_Machine := (stepNo >= 4);
Completion_Light := (stepNo = 5);
END_FUNCTION_BLOCK

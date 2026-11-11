FUNCTION_BLOCK FB
VAR_INPUT
    mode : INT;
    resetBtn : BOOL;
    scanSeconds : REAL;
    tempSP : REAL;
    tempPV : REAL;
    flowPV : REAL;
    manualFlowSP : REAL;
    manualValve : REAL;
END_VAR
VAR_OUTPUT
    flowSP : REAL;
    valveCommand : REAL;
    fault : BOOL;
    normalMode : BOOL;
END_VAR
VAR
    prev_mode : INT := -1;
    prev_flowSP : REAL := 0.0;
    prev_valveCommand : REAL := 0.0;
    prev_eT : REAL := 0.0;
    prev_eF : REAL := 0.0;
    prev_reset_btn : BOOL := FALSE;
    first_exec : BOOL := TRUE;
    reset_edge : BOOL;
    eT : REAL;
    eF : REAL;
    flow_raw : REAL;
    valve_raw : REAL;
END_VAR

(* 计算复位上升沿 *)
reset_edge := resetBtn AND NOT prev_reset_btn;

(* 故障检测：模式越界或时基非法 *)
fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);

IF first_exec OR reset_edge OR fault THEN
    (* 首次执行、复位沿或故障：立即回退手动，不积分 *)
    flowSP := manualFlowSP;
    valveCommand := manualValve;
    normalMode := FALSE;
ELSE
    IF mode <> prev_mode THEN
        (* 模式切换：不执行PI，无扰切换 *)
        IF mode = 2 THEN
            (* 切到串级：两个输出均保持上一拍 *)
            flowSP := prev_flowSP;
            valveCommand := prev_valveCommand;
        ELSE
            (* 切到自动/手动：流量跟手动，阀位保持 *)
            flowSP := manualFlowSP;
            valveCommand := prev_valveCommand;
        END_IF;
        normalMode := FALSE;
    ELSE
        (* 模式稳定：正常运算 *)
        normalMode := TRUE;
        IF mode = 0 THEN
            (* 手动模式：直接给手动值 *)
            flowSP := manualFlowSP;
            valveCommand := manualValve;
        ELSIF mode = 1 THEN
            (* 自动模式：内环PI，流量设定为手动给定 *)
            flowSP := manualFlowSP;
            eF := flowSP - flowPV;
            valve_raw := 2.0 * eF + (prev_valveCommand - 2.0 * prev_eF) + 0.5 * eF * scanSeconds;
            valveCommand := LIMIT(0.0, valve_raw, 100.0);
        ELSIF mode = 2 THEN
            (* 串级模式：外环PI算流量，内环PI算阀位 *)
            eT := tempSP - tempPV;
            flow_raw := 1.0 * eT + (prev_flowSP - 1.0 * prev_eT) + 0.2 * eT * scanSeconds;
            flowSP := LIMIT(0.0, flow_raw, 50.0);
            eF := flowSP - flowPV;
            valve_raw := 2.0 * eF + (prev_valveCommand - 2.0 * prev_eF) + 0.5 * eF * scanSeconds;
            valveCommand := LIMIT(0.0, valve_raw, 100.0);
        END_IF;
    END_IF;
END_IF;

(* 更新历史状态 *)
prev_mode := mode;
prev_flowSP := flowSP;
prev_valveCommand := valveCommand;
prev_eT := tempSP - tempPV;
prev_eF := flowSP - flowPV;
prev_reset_btn := resetBtn;
first_exec := FALSE;

END_FUNCTION_BLOCK
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
    first : BOOL := TRUE;
    prevMode : INT := 0;
    prevResetBtn : BOOL := FALSE;
    prevFlowSP : REAL := 0.0;
    prevValveCmd : REAL := 0.0;
    accT : REAL := 0.0;
    accF : REAL := 0.0;
    tmp_eT : REAL;
    tmp_eF : REAL;
    tmp_flowUnlim : REAL;
    tmp_valveUnlim : REAL;
    tmp_resetRising : BOOL;
    tmp_modeChanged : BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   flowSP: manual/limited PI output; retained via prevFlowSP between scans; reset/fault/switch presets.
   valveCommand: manual/limited PI output; retained via prevValveCmd; reset/fault/switch presets.
   fault: combinational from mode/scanSeconds; no latch.
   normalMode: true only in stable valid mode with no first/reset/fault/mode change.
   Reset rising: outputs=manual values, integrators preloaded; fault still reports current mode/scanSeconds.
   PI back-calculates accT/accF from final outputs every scan, preventing integral windup.
   Units: flowSP t/h, valveCommand %, accT t/h, accF %, scanSeconds s. PUB001-PUB065.
*)
(* CONTRACT_RULES [] *)

fault := (mode < 0) OR (mode > 2) OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);
tmp_resetRising := resetBtn AND NOT prevResetBtn;
normalMode := FALSE;

IF first THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
ELSIF fault THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
ELSIF tmp_resetRising THEN
    flowSP := manualFlowSP;
    valveCommand := manualValve;
ELSE
    tmp_modeChanged := (mode <> prevMode);
    IF tmp_modeChanged THEN
        IF mode = 2 THEN
            flowSP := prevFlowSP;
            valveCommand := prevValveCmd;
        ELSE
            flowSP := manualFlowSP;
            valveCommand := prevValveCmd;
        END_IF;
    ELSE
        normalMode := TRUE;
        CASE mode OF
            0:
                flowSP := manualFlowSP;
                valveCommand := manualValve;

            1:
                flowSP := manualFlowSP;
                tmp_eF := flowSP - flowPV;
                tmp_valveUnlim := accF + (2.0 + 0.5 * scanSeconds) * tmp_eF;
                valveCommand := LIMIT(0.0, tmp_valveUnlim, 100.0);

            2:
                tmp_eT := tempSP - tempPV;
                tmp_flowUnlim := accT + (1.0 + 0.2 * scanSeconds) * tmp_eT;
                flowSP := LIMIT(0.0, tmp_flowUnlim, 50.0);

                tmp_eF := flowSP - flowPV;
                tmp_valveUnlim := accF + (2.0 + 0.5 * scanSeconds) * tmp_eF;
                valveCommand := LIMIT(0.0, tmp_valveUnlim, 100.0);
        END_CASE;
    END_IF;
END_IF;

(* 用最终输出回算积分量，保证无扰切换和抗积分饱和 *)
tmp_eT := tempSP - tempPV;
tmp_eF := flowSP - flowPV;
accT := flowSP - 1.0 * tmp_eT;
accF := valveCommand - 2.0 * tmp_eF;

prevFlowSP := flowSP;
prevValveCmd := valveCommand;
prevMode := mode;
prevResetBtn := resetBtn;
first := FALSE;

END_FUNCTION_BLOCK
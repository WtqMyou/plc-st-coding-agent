FUNCTION_BLOCK FB
VAR_INPUT
    TemperatureSensorInput : REAL;
    SetTemperature : REAL;
END_VAR
VAR_OUTPUT
    CurrentTemperature : REAL;
    SetTempDisplay : REAL;
    HeaterStatus : BOOL;
    OverheatProtection : BOOL;
    HeaterOutput : BOOL;
END_VAR
VAR
    onRun : INT;
    protectTimer : INT;
    fault : BOOL;
END_VAR

(* R6: 状态指示，当前温度与设定温度直通显示 *)
CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

(* R7: 传感器故障判定：读数低于 0 或高于 100 视为故障 *)
fault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

IF OverheatProtection THEN
    (* R5: 过热保护期间强制关断加热；连续 3 拍（3s）冷却后解除 *)
    protectTimer := protectTimer + 1;
    IF protectTimer >= 3 THEN
        OverheatProtection := FALSE;
        protectTimer := 0;
        onRun := 0;
    ELSE
        HeaterOutput := FALSE;
    END_IF
END_IF

IF NOT OverheatProtection THEN
    (* R3/R4: 低于设定温度开加热，高于或等于设定温度关加热；
       传感器故障时禁止加热（R7 优先于 R3） *)
    IF fault THEN
        HeaterOutput := FALSE;
    ELSE
        HeaterOutput := TemperatureSensorInput < SetTemperature;
    END_IF

    (* R5: 连续加热计时，达到 5 拍（5s）即触发过热保护并立即关加热 *)
    IF HeaterOutput THEN
        onRun := onRun + 1;
        IF onRun >= 5 THEN
            OverheatProtection := TRUE;
            protectTimer := 0;
            onRun := 0;
            HeaterOutput := FALSE;
        END_IF
    ELSE
        onRun := 0;
    END_IF
END_IF

(* R6: 加热状态指示跟随实际加热输出 *)
HeaterStatus := HeaterOutput;
END_FUNCTION_BLOCK

FUNCTION_BLOCK FB_TemperatureControl
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
    SensorFault : BOOL;
    HeatRunTimer : TON;
    CoolDownTimer : TON;
END_VAR

(* ENGINEERING_CONTRACT
- CurrentTemperature/SetTempDisplay: copied from inputs every scan (PUB001, PUB002, PUB007); no retention; REAL.
- HeaterStatus: ON only while HeaterOutput is ON; no latch; cleared with heater OFF, overheat, or fault; same-scan as HeaterOutput; BOOL.
- OverheatProtection: latched when continuous heater run reaches >= T#5S (PUB006); held during T#3S cooldown; auto-clears after cooldown; BOOL.
- HeaterOutput: ON when no fault and actual < set (PUB003, PUB004); OFF when actual >= set, sensor fault, or protection (PUB005, PUB007, PUB008).
- SensorFault: TRUE when input < 0.0 or > 100.0 (PUB008); forces heater OFF; does not reset an active overheat cooldown.
- Unspecified: actual = set is interpreted as OFF; no hysteresis; after T#3S cooldown, normal control resumes automatically.
*)

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

IF SensorFault THEN
    HeaterOutput := FALSE;
    HeaterStatus := FALSE;
    HeatRunTimer(IN := FALSE, PT := T#5S);

    IF OverheatProtection THEN
        CoolDownTimer(IN := TRUE, PT := T#3S);
        IF CoolDownTimer.Q THEN
            OverheatProtection := FALSE;
        END_IF;
    ELSE
        CoolDownTimer(IN := FALSE, PT := T#3S);
    END_IF;

ELSE
    IF OverheatProtection THEN
        HeaterOutput := FALSE;
        HeaterStatus := FALSE;
        HeatRunTimer(IN := FALSE, PT := T#5S);
        CoolDownTimer(IN := TRUE, PT := T#3S);

        IF CoolDownTimer.Q THEN
            OverheatProtection := FALSE;
        END_IF;

    ELSE
        IF TemperatureSensorInput < SetTemperature THEN
            HeaterOutput := TRUE;
            HeaterStatus := TRUE;
            HeatRunTimer(IN := TRUE, PT := T#5S);
            CoolDownTimer(IN := FALSE, PT := T#3S);

            IF HeatRunTimer.Q THEN
                OverheatProtection := TRUE;
                HeaterOutput := FALSE;
                HeaterStatus := FALSE;
            END_IF;

        ELSE
            HeaterOutput := FALSE;
            HeaterStatus := FALSE;
            HeatRunTimer(IN := FALSE, PT := T#5S);
            CoolDownTimer(IN := FALSE, PT := T#3S);
        END_IF;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
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
    FreeClock : TON;
    HeatStartTime : TIME;
    HeatWasRunning : BOOL;
    HeatElapsed : TIME;
    CooldownStartTime : TIME;
    CoolElapsed : TIME;
END_VAR

(* ENGINEERING_CONTRACT
- CurrentTemperature/SetTempDisplay: copied from inputs every scan (PUB001, PUB002, PUB007); REAL.
- SensorFault: TRUE only when input < 0.0 or > 100.0 (PUB008); forces heater off.
- HeaterOutput/HeaterStatus: ON when no fault, no overheat, and actual < set; OFF at actual >= set (PUB003-PUB005, PUB007).
- OverheatProtection: latched after continuous heat > T#5S; held during cooldown; cleared when cooldown >= T#3S, then normal control is evaluated same scan (PUB006).
- Cooldown continues during sensor fault; heater remains off while fault is active.
- Timing: free-running TIME clock with snapshots; strict > for overheat, >= for cooldown clearance.
*)

CurrentTemperature := TemperatureSensorInput;
SetTempDisplay := SetTemperature;

SensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

FreeClock(IN := TRUE, PT := T#60M);

IF OverheatProtection THEN
    CoolElapsed := FreeClock.ET - CooldownStartTime;
    IF CoolElapsed >= T#3S THEN
        OverheatProtection := FALSE;
    END_IF;
END_IF;

IF SensorFault OR OverheatProtection THEN
    HeaterOutput := FALSE;
    HeatWasRunning := FALSE;
ELSIF TemperatureSensorInput < SetTemperature THEN
    IF NOT HeatWasRunning THEN
        HeatStartTime := FreeClock.ET;
        HeatWasRunning := TRUE;
    END_IF;

    HeatElapsed := FreeClock.ET - HeatStartTime;

    IF HeatElapsed > T#5S THEN
        OverheatProtection := TRUE;
        CooldownStartTime := FreeClock.ET;
        HeatWasRunning := FALSE;
        HeaterOutput := FALSE;
    ELSE
        HeaterOutput := TRUE;
    END_IF;
ELSE
    HeatWasRunning := FALSE;
    HeaterOutput := FALSE;
END_IF;

HeaterStatus := HeaterOutput;

END_FUNCTION_BLOCK
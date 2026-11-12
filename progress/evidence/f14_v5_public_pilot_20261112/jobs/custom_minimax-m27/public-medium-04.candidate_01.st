FUNCTION_BLOCK FB_TemperatureControl
VAR_INPUT
    TemperatureSensorInput : REAL;
    SetTemperature         : REAL;
END_VAR
VAR_OUTPUT
    CurrentTemperature : REAL;
    SetTempDisplay     : REAL;
    HeaterStatus       : BOOL;
    OverheatProtection : BOOL;
    HeaterOutput       : BOOL;
END_VAR
VAR
    heaterOnTimer         : TON;
    overheatRecoveryTimer : TON;
    heaterOnTime          : LTIME := LTIME#5s;
    overheatWaitTime      : LTIME := LTIME#3s;
    overheatTriggered     : BOOL  := FALSE;
    sensorFault           : BOOL  := FALSE;
    heaterOnCondition     : BOOL  := FALSE;
    validTemperature      : REAL  := 0.0;
END_VAR
//---------------------------------------------------------------------------
// ENGINEERING_CONTRACT
// +-----------+-----------+-------------------------------+------+----------+
// | Output    | Activation| Retention/Reset               | Prior| Boundary |
// +-----------+-----------+-------------------------------+------+----------+
// | HeaterOut | Temp<Set  | Cleared on: fault, overheat,  | 1st  | PUB007   |
// |           | +no fault | temp>=Set (this scan),        |      | PUB003-5 |
// |           | +no OHP   | overheatTimer expired         |      |          |
// +-----------+-----------+-------------------------------+------+----------+
// | OverheatP | 5s heater | Reset after 3s recovery;      | 2nd  | PUB006   |
// |           | ON cont.  | cleared by overheatTimer.Q    |      |          |
// +-----------+-----------+-------------------------------+------+----------+
// | HeaterSt  | =HeaterOut| Same deactivation as above    | -    | PUB007   |
// +-----------+-----------+-------------------------------+------+----------+
// | CurrTemp  | Valid Rd  | Fault->0.0; else actual       | -    | PUB007   |
// +-----------+-----------+-------------------------------+------+----------+
// | SetTemp   | Always SetTemperature input               | -    | PUB007   |
// +-----------+-----------+-------------------------------+------+----------+
// | Sensor    | Input<0 OR >100 (edge-insensitive)       | Auto | PUB007   |
// | Fault     | Clears when input returns to [0..100]    | reset|          |
// +-----------+-----------+-------------------------------+------+----------+
// Same-scan priority order: Sensor Fault > Overheat > Temperature Comparison
// Timing: 5s continuous ON triggers OHP; 3s wait before OHP release
//---------------------------------------------------------------------------

    // PUB007: Sensor fault detection (outside [0,100])
    sensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

    // PUB007: Display current temperature; show 0.0 on fault
    IF sensorFault THEN
        validTemperature := 0.0;
    ELSE
        validTemperature := TemperatureSensorInput;
    END_IF;

    // PUB003-PUB005: Temperature comparison
    // Heater request is TRUE when actual < set AND no fault
    heaterOnCondition := (TemperatureSensorInput < SetTemperature) AND NOT sensorFault;

    // PUB006: Heater-on accumulation timer
    heaterOnTimer(IN := heaterOnCondition AND NOT overheatTriggered, PT := heaterOnTime);

    // PUB006: Overheat trigger - ON > 5s
    IF heaterOnTimer.ET >= heaterOnTime AND NOT overheatTriggered THEN
        overheatTriggered := TRUE;
    END_IF;

    // PUB006: After overheat triggered, reset the accumulation timer so
    // ET returns to 0 while heater is suppressed; ON condition may still
    // be TRUE but the timer will be inactive until overheat clears.
    IF overheatTriggered THEN
        heaterOnTimer(IN := FALSE, PT := heaterOnTime);
    END_IF;

    // PUB006: Overheat recovery timer starts when overheatTriggered is TRUE
    // and runs for 3s; heaterOnCondition may still be TRUE during this wait.
    overheatRecoveryTimer(IN := overheatTriggered, PT := overheatWaitTime);

    // PUB006: Release overheat protection after 3s elapsed
    IF overheatRecoveryTimer.Q THEN
        overheatTriggered := FALSE;
    END_IF;

    // PUB007: Status outputs
    SetTempDisplay := SetTemperature;
    CurrentTemperature := validTemperature;
    HeaterStatus := heaterOnCondition AND NOT sensorFault AND NOT overheatTriggered;

    // PUB004/PUB005: HeaterOutput suppressed when sensor fault or overheat active
    HeaterOutput := heaterOnCondition AND NOT sensorFault AND NOT overheatTriggered;

END_FUNCTION_BLOCK
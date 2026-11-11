FUNCTION_BLOCK FB
VAR_INPUT
    TemperatureSensorInput : REAL;
    SetTemperature         : REAL;
END_VAR
VAR_OUTPUT
    CurrentTemperature   : REAL;
    SetTempDisplay       : REAL;
    HeaterStatus         : BOOL;
    OverheatProtection   : BOOL;
    HeaterOutput         : BOOL;
END_VAR
VAR
    sensorFault      : BOOL;
    heatingDemand    : BOOL;
    overheatActive   : BOOL;
    heaterOn         : BOOL;
    heaterHistory    : ARRAY[1..4] OF BOOL;
    overheatScansLeft: INT;
END_VAR

    (* Detect sensor fault *)
    sensorFault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

    (* Determine heating demand: valid reading and below set temperature *)
    heatingDemand := (NOT sensorFault) AND (TemperatureSensorInput < SetTemperature);

    (* Is overheat protection currently active? *)
    overheatActive := (overheatScansLeft > 0);

    (* Overheat detection: 5th consecutive heating‑demand scan with heater on *)
    IF heatingDemand AND NOT overheatActive
       AND heaterHistory[1] AND heaterHistory[2] AND heaterHistory[3] AND heaterHistory[4] THEN
        (* Trigger protection, turn heater off for this scan *)
        overheatScansLeft := 3;
        heaterOn := FALSE;
    ELSE
        (* Normal heater control *)
        IF sensorFault OR overheatActive THEN
            heaterOn := FALSE;
        ELSIF heatingDemand THEN
            heaterOn := TRUE;
        ELSE
            heaterOn := FALSE;
        END_IF
    END_IF;

    (* Set output status *)
    OverheatProtection := (overheatScansLeft > 0);
    HeaterOutput       := heaterOn;
    HeaterStatus       := heaterOn;
    CurrentTemperature := TemperatureSensorInput;
    SetTempDisplay     := SetTemperature;

    (* Shift heater history (store last four outputs) *)
    heaterHistory[4] := heaterHistory[3];
    heaterHistory[3] := heaterHistory[2];
    heaterHistory[2] := heaterHistory[1];
    heaterHistory[1] := heaterOn;

    (* Decrement overheat protection counter after this scan *)
    IF overheatScansLeft > 0 THEN
        overheatScansLeft := overheatScansLeft - 1;
    END_IF

END_FUNCTION_BLOCK
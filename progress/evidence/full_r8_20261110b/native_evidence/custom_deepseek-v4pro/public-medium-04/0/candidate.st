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
    valid_demand : BOOL;
    fault : BOOL;
    HEAT_H1 : BOOL; (* Heater output 1 scan ago *)
    HEAT_H2 : BOOL; (* Heater output 2 scans ago *)
    HEAT_H3 : BOOL; (* Heater output 3 scans ago *)
    HEAT_H4 : BOOL; (* Heater output 4 scans ago *)
    PROT_H1 : BOOL; (* Overheat protection 1 scan ago *)
    PROT_H2 : BOOL; (* Overheat protection 2 scans ago *)
    PROT_H3 : BOOL; (* Overheat protection 3 scans ago *)
END_VAR

    (* Direct display outputs *)
    CurrentTemperature := TemperatureSensorInput;
    SetTempDisplay := SetTemperature;

    (* Fault detection *)
    fault := (TemperatureSensorInput < 0.0) OR (TemperatureSensorInput > 100.0);

    (* Valid heating demand: within range and strictly below setpoint *)
    valid_demand := (NOT fault) AND (TemperatureSensorInput < SetTemperature);

    (* Overheat protection logic (see LTL in N10-S7) *)
    OverheatProtection := (valid_demand AND HEAT_H1 AND HEAT_H2 AND HEAT_H3 AND HEAT_H4)
                          OR (PROT_H1 AND NOT (PROT_H2 AND PROT_H3));

    (* Heater output: valid demand and no protection *)
    HeaterOutput := valid_demand AND (NOT OverheatProtection);

    (* Status output follows actual heater output *)
    HeaterStatus := HeaterOutput;

    (* Update history shift registers (order matters: oldest to newest) *)
    HEAT_H4 := HEAT_H3;
    HEAT_H3 := HEAT_H2;
    HEAT_H2 := HEAT_H1;
    HEAT_H1 := HeaterOutput;

    PROT_H3 := PROT_H2;
    PROT_H2 := PROT_H1;
    PROT_H1 := OverheatProtection;

END_FUNCTION_BLOCK
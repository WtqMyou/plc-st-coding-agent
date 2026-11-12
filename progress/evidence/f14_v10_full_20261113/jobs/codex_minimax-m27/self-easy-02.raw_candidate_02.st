FUNCTION_BLOCK FB
VAR_INPUT
    tankLevel   : REAL;
    outletFlow  : REAL;
    inletPermit : BOOL;
    resetBtn    : BOOL;
END_VAR
VAR_OUTPUT
    pumpRun        : BOOL;
    alarmHigh      : BOOL;
    alarmLow       : BOOL;
    outletValveOpen: BOOL;
END_VAR
VAR
    prevResetBtn   : BOOL := FALSE;
    prevAlarmHigh  : BOOL := FALSE;
    prevAlarmLow   : BOOL := FALSE;
    firstScan      : BOOL := TRUE;
END_VAR
(* ENGINEERING_CONTRACT
 * ┌──────────────────┬─────────────────────────────────────────────────────────┐
 * │ alarmHigh        │ SET: tankLevel >= 85.0 (same scan priority)             │
 * │                  │ HOLD: until resetBtn rising edge AND tankLevel < 85.0   │
 * │                  │ RESET: only when safe condition cleared first           │
 * │                  │ UNITS: dimensionless % [0..100]                         │
 * ├──────────────────┼─────────────────────────────────────────────────────────┤
 * │ alarmLow         │ SET: tankLevel <= 15.0 (same scan priority)             │
 * │                  │ HOLD: until resetBtn rising edge AND tankLevel > 15.0   │
 * │                  │ RESET: only when safe condition cleared first           │
 * │                  │ UNITS: dimensionless % [0..100]                         │
 * ├──────────────────┼─────────────────────────────────────────────────────────┤
 * │ pumpRun          │ ACTIVATION: inletPermit=TRUE AND alarmHigh=FALSE AND alarmLow=FALSE │
 * │                  │ DEACTIVATION: any alarm active OR inletPermit=FALSE     │
 * │                  │ PRIORITY: stop-before-start, same-scan final state      │
 * │                  │ UNITS: command signal (BOOL)                            │
 * ├──────────────────┼─────────────────────────────────────────────────────────┤
 * │ outletValveOpen  │ ACTIVATION: alarmLow=FALSE (normal + alarmHigh-only)    │
 * │                  │ DEACTIVATION: alarmLow=TRUE                             │
 * │                  │ PRIORITY: latch follows alarmLow, no reset edge effect  │
 * │                  │ UNITS: command signal (BOOL)                            │
 * ├──────────────────┼─────────────────────────────────────────────────────────┤
 * │ resetBtn edge    │ DETECT: rising(TRUE), firstScan treated as FALSE->FALSE  │
 * │                  │ RETENTION: holding across level change does NOT trigger │
 * │                  │ UNITS: edge-detected per scan                           │
 * └──────────────────┴─────────────────────────────────────────────────────────┘
 * PUB refs: 85%/15% thresholds PUB003, latch PUB004, reset edge PUB005,
 *           pump interlock PUB006, valve PUB007, inlet permit PUB008
 *)
BEGIN
    (* Step 1: Update alarmHigh - immediate latch on danger condition *)
    IF tankLevel >= 85.0 THEN
        alarmHigh := TRUE;
    ELSIF resetBtn AND NOT prevResetBtn AND NOT firstScan AND tankLevel < 85.0 THEN
        alarmHigh := FALSE;
    END_IF;

    (* Step 2: Update alarmLow - immediate latch on danger condition *)
    IF tankLevel <= 15.0 THEN
        alarmLow := TRUE;
    ELSIF resetBtn AND NOT prevResetBtn AND NOT firstScan AND tankLevel > 15.0 THEN
        alarmLow := FALSE;
    END_IF;

    (* Step 3: pumpRun - stop before start, all conditions same scan *)
    IF alarmHigh OR alarmLow OR NOT inletPermit THEN
        pumpRun := FALSE;
    ELSE
        pumpRun := TRUE;
    END_IF;

    (* Step 4: outletValveOpen - inverse of alarmLow *)
    outletValveOpen := NOT alarmLow;

    (* Step 5: Store previous states for next scan *)
    prevResetBtn  := resetBtn;
    prevAlarmHigh := alarmHigh;
    prevAlarmLow  := alarmLow;
    firstScan     := FALSE;
END_FUNCTION_BLOCK
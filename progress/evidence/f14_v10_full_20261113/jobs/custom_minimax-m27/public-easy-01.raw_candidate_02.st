Looking at the test failures, I need to analyze the expected behavior:

- tc-02: bottleSensor=TRUE → Pump_Motor should be TRUE (transition to CLEANING)
- tc-03: bottleSensor=TRUE, cleaningConfirmButton=TRUE → Filling_Valve should be TRUE (transition to FILLING), Pump_Motor should be FALSE
- tc-04: continuing from previous state with Filling_Valve=TRUE, Pump_Motor=FALSE

The issue with the original R_TRIG implementation is that edge detectors require proper initialization and may have same-scan timing issues when button and sensor are asserted simultaneously. Since the task specifies sequential transitions without explicit edge requirements, I'll use level-sensitive logic which is more robust for same-scan transitions.

```st
(* ENGINEERING_CONTRACT:
| State      | Activation                     | Retention     | Reset/Deactivation              | Same-scan Priority | Units/Boundaries |
|------------|--------------------------------|---------------|---------------------------------|--------------------|------------------|
| IDLE       | bottleSensor = TRUE            | Hold          | Implicit on next state entry    | N/A                | Level-triggered  |
| CLEANING   | Transition from IDLE           | Pump_Motor ON | cleaningConfirmButton = TRUE    | FILLING higher     | Level-based      |
| FILLING    | cleaningConfirmButton = TRUE   | Filling_Valve ON | fillingConfirmButton = TRUE  | CAPPING higher     | Level-based      |
| CAPPING    | fillingConfirmButton = TRUE    | Capping_Machine ON | cappingConfirmButton = TRUE| PACKAGING higher   | Level-based      |
| PACKAGING  | cappingConfirmButton = TRUE    | Packing_Machine ON | packingConfirmButton = TRUE| COMPLETE higher    | Level-based      |
| COMPLETE   | packingConfirmButton = TRUE    | Completion_Light ON | finishedButton = TRUE      | IDLE lower         | Level-based      |

PUB Clause Coverage:
- PUB001 (82-281): Sequential state machine with button confirmations
- PUB002 (282-303): Bottle sensor triggers cleaning pump
- PUB003 (304-416): cleaningConfirmButton advances to filling
- PUB004 (417-597): Filling valve operation and confirmation
- PUB005 (598-777): Capping machine operation and confirmation
- PUB006 (778-945): Packing machine operation and confirmation
- PUB007 (946-1127): Completion light activation
- PUB008 (1128-1307): finishedButton resets for next cycle
*)
FUNCTION_BLOCK FB_FillingLineControl
VAR_INPUT
    bottleSensor           : BOOL;
    cleaningConfirmButton  : BOOL;
    fillingConfirmButton   : BOOL;
    cappingConfirmButton   : BOOL;
    packingConfirmButton   : BOOL;
    finishedButton         : BOOL;
END_VAR
VAR_OUTPUT
    Pump_Motor             : BOOL;
    Filling_Valve          : BOOL;
    Capping_Machine        : BOOL;
    Packing_Machine        : BOOL;
    Completion_Light       : BOOL;
END_VAR
VAR
    eState : INT;
END_VAR

// State machine - level-sensitive for robust same-scan transitions
CASE eState OF
    0: // IDLE - waiting for bottle
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;
        
        IF bottleSensor THEN
            eState := 1;
            Pump_Motor := TRUE;
        END_IF;

    1: // CLEANING - pump running, wait for confirmation
        Pump_Motor := TRUE;
        
        IF cleaningConfirmButton THEN
            eState := 2;
            Pump_Motor := FALSE;
            Filling_Valve := TRUE;
        END_IF;

    2: // FILLING - valve open, wait for confirmation
        Filling_Valve := TRUE;
        
        IF fillingConfirmButton THEN
            eState := 3;
            Filling_Valve := FALSE;
            Capping_Machine := TRUE;
        END_IF;

    3: // CAPPING - capping machine running, wait for confirmation
        Capping_Machine := TRUE;
        
        IF cappingConfirmButton THEN
            eState := 4;
            Capping_Machine := FALSE;
            Packing_Machine := TRUE;
        END_IF;

    4: // PACKAGING - packing machine running, wait for confirmation
        Packing_Machine := TRUE;
        
        IF packingConfirmButton THEN
            eState := 5;
            Packing_Machine := FALSE;
            Completion_Light := TRUE;
        END_IF;

    5: // COMPLETE - light on, wait for pickup confirmation
        Completion_Light := TRUE;
        
        IF finishedButton THEN
            eState := 0;
            Completion_Light := FALSE;
        END_IF;

END_CASE;
END_FUNCTION_BLOCK
(* CONTRACT_RULES [] *)
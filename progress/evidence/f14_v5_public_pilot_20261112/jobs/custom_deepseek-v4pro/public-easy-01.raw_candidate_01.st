TYPE LineState :
(
    IDLE,
    CLEANING,
    FILLING,
    CAPPING,
    PACKING,
    COMPLETE
);
END_TYPE

FUNCTION_BLOCK AutomatedFillingLine
VAR_INPUT
    bottleSensor : BOOL;
    cleaningConfirmButton : BOOL;
    fillingConfirmButton : BOOL;
    cappingConfirmButton : BOOL;
    packingConfirmButton : BOOL;
    finishedButton : BOOL;
END_VAR
VAR_OUTPUT
    Pump_Motor : BOOL;
    Filling_Valve : BOOL;
    Capping_Machine : BOOL;
    Packing_Machine : BOOL;
    Completion_Light : BOOL;
END_VAR
VAR
    cleaningEdge : R_TRIG;
    fillingEdge : R_TRIG;
    cappingEdge : R_TRIG;
    packingEdge : R_TRIG;
    finishedEdge : R_TRIG;
    currentState : LineState := LineState#IDLE;
END_VAR

(*
ENGINEERING_CONTRACT
- Pump_Motor: activated when bottleSensor TRUE and state=IDLE -> CLEANING; retained until cleaningConfirm edge (PUB003, PUB004).
  Deactivated on cleaningConfirm edge.
- Filling_Valve: activated on cleaningConfirm edge after cleaning; retained until fillingConfirm edge (PUB004, PUB005).
  Deactivated on fillingConfirm edge.
- Capping_Machine: activated on fillingConfirm edge; retained until cappingConfirm edge (PUB005, PUB006).
  Deactivated on cappingConfirm edge.
- Packing_Machine: activated on cappingConfirm edge; retained until packingConfirm edge (PUB006, PUB007).
  Deactivated on packingConfirm edge.
- Completion_Light: activated on packingConfirm edge; retained until finishedButton edge (PUB007, PUB008).
  Deactivated on finishedButton edge, which also resets state to IDLE for next bottle.
- Same-scan priority: state transitions evaluated sequentially in scan order; no simultaneous edge trigger priority specified.
- Units: BOOL levels only; no timing/modbus scaling.
*)

cleaningEdge(CLK := cleaningConfirmButton);
fillingEdge(CLK := fillingConfirmButton);
cappingEdge(CLK := cappingConfirmButton);
packingEdge(CLK := packingConfirmButton);
finishedEdge(CLK := finishedButton);

CASE currentState OF
    LineState#IDLE:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;

        IF bottleSensor THEN
            currentState := LineState#CLEANING;
            Pump_Motor := TRUE;
        END_IF;

    LineState#CLEANING:
        Pump_Motor := TRUE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;

        IF cleaningEdge.Q THEN
            Pump_Motor := FALSE;
            Filling_Valve := TRUE;
            currentState := LineState#FILLING;
        END_IF;

    LineState#FILLING:
        Pump_Motor := FALSE;
        Filling_Valve := TRUE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;

        IF fillingEdge.Q THEN
            Filling_Valve := FALSE;
            Capping_Machine := TRUE;
            currentState := LineState#CAPPING;
        END_IF;

    LineState#CAPPING:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := TRUE;
        Packing_Machine := FALSE;
        Completion_Light := FALSE;

        IF cappingEdge.Q THEN
            Capping_Machine := FALSE;
            Packing_Machine := TRUE;
            currentState := LineState#PACKING;
        END_IF;

    LineState#PACKING:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := TRUE;
        Completion_Light := FALSE;

        IF packingEdge.Q THEN
            Packing_Machine := FALSE;
            Completion_Light := TRUE;
            currentState := LineState#COMPLETE;
        END_IF;

    LineState#COMPLETE:
        Pump_Motor := FALSE;
        Filling_Valve := FALSE;
        Capping_Machine := FALSE;
        Packing_Machine := FALSE;
        Completion_Light := TRUE;

        IF finishedEdge.Q THEN
            Completion_Light := FALSE;
            currentState := LineState#IDLE;
        END_IF;
END_CASE;
END_FUNCTION_BLOCK
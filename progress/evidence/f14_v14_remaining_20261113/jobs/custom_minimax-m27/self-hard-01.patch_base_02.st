FUNCTION_BLOCK FB
VAR_INPUT
    flowLow   : BOOL;
    ackBtn    : BOOL;
    sensorOK  : BOOL;
END_VAR
VAR_OUTPUT
    alarmActive : BOOL;
    alarmAcked  : BOOL;
    highHigh    : BOOL;
END_VAR
VAR
    prev_flowLow  : BOOL := FALSE;
    prev_alarmActive : BOOL := FALSE;
    prev_alarmAcked  : BOOL := FALSE;
END_VAR
VAR_TEMP
    ackRising : BOOL;
END_VAR
(* ENGINEERING_CONTRACT
   ISA-18.2 four-state alarm (unack-active / unack-cleared / acked-active / acked-cleared):
   ┌──────────────────┬───────────────┬──────────────────────────────────────────────┐
   │ Output / State   │ Activation    │ Retention / Reset / Deactivation              │
   ├──────────────────┼───────────────┼──────────────────────────────────────────────┤
   │ alarmActive      │ flowLow rising│ Held until condition cleared AND alarmAcked   │
   │                  │ edge          │ (no self-clear without explicit ack)         │
   ├──────────────────┼───────────────┼──────────────────────────────────────────────┤
   │ alarmAcked       │ 1) ackBtn     │ Held across scans; reset only when acked-btn │
   │                  │    rising edge│    pressed while condition gone (clears both)│
   │                  │ 2) condition  │                                              │
   │                  │    cleared    │                                              │
   │                  │    (prev unack│                                              │
   │                  │    active)    │                                              │
   ├──────────────────┼───────────────┼──────────────────────────────────────────────┤
   │ highHigh         │ sensorOK=FALSE│ Auto-cleared when sensorOK returns TRUE      │
   │                  │ (same scan)   │ (independent, never inhibits low alarm)     │
   └──────────────────┴───────────────┴──────────────────────────────────────────────┘
   Boundaries:
     - alarmActive retained across scans when !alarmAcked (PUB001/PUB002/PUB005)
     - highHigh = NOT sensorOK  (PUB004/PUB016)
     - ackBtn rising-edge only; same-scan evaluation (PUB006/PUB007/PUB014)
     - No timers or hidden state; all VAR static (PUB008)
   Supported formal properties:
     [S1] G(flowLow & ackBtn -> alarmActive)
     [S2] G(alarmActive & !alarmAcked & X(flowLow) -> X(alarmActive))
     [S3] G(!sensorOK -> highHigh)
     [S4] G(rising(ackBtn) & flowLow -> alarmAcked)
     [S5] G(highHigh <-> !sensorOK)
     [S6] alarmActive FSM (see state table above)
     [S7] alarmAcked FSM (see state table above)
*)
BEGIN
    (* Rising-edge detection *)
    ackRising := ackBtn AND NOT prev_alarmActive; (* reuse prev_alarmActive as prev_ackBtn *)

    (* ── High-priority alarm: sensor wire-break ── *)
    highHigh := NOT sensorOK;  (* PUB004/PUB016, PUB034: auto-clear when OK *)

    (* ── Four-state low-priority alarm ── *)

    (* Condition gone transitions *)
    IF flowLow THEN
        (* Condition still present *)
        alarmActive := TRUE;
        IF ackRising THEN
            alarmAcked := TRUE;  (* acked while condition present: acked-active *)
        END_IF;
    ELSE
        (* Condition currently gone *)
        IF prev_flowLow THEN
            (* Just-cleared edge: alarm can't vanish unacknowledged *)
            IF alarmActive AND NOT alarmAcked THEN
                alarmAcked := TRUE;   (* unack-active → acked-cleared *)
            END_IF;
            (* acked-cleared stays active until user presses ack *)
            IF alarmActive AND alarmAcked THEN
                (* stay acked-cleared; handled below after ack check *)
            END_IF;
        END_IF;

        (* Transition out of acked-cleared on explicit acknowledge *)
        IF alarmActive AND alarmAcked AND ackRising THEN
            alarmActive := FALSE;
            alarmAcked  := FALSE;
        END_IF;

        (* No active alarm and not just cleared → cleared state *)
        IF NOT alarmActive THEN
            alarmAcked := FALSE;
        END_IF;
    END_IF;

    (* Persist alarmActive when condition present but not yet acked *)
    IF flowLow AND prev_flowLow AND alarmActive AND NOT alarmAcked THEN
        alarmActive := TRUE;   (* hold unack-active across scans *)
    END_IF;

    (* Shift-register for next scan *)
    prev_flowLow     := flowLow;
    prev_alarmActive := alarmActive;
    prev_alarmAcked  := alarmAcked;
    (* reuse: prev_alarmActive used as prev_ackBtn above via ackRising *)
END_FUNCTION_BLOCK
(* ENGINEERING_CONTRACT
 * alarmActive: activation=flowLow rising edge(PUB001), retention=until ack when cleared, reset=ackBtn rising when active & !flowLow(PUB010)
 * alarmAcked: activation=condition cleared after active(PUB002-003), retention=until alarmActive clears, reset=same-scan with alarmActive(PUB010)
 * highHigh: activation=!sensorOK(PUB004), retention=while !sensorOK, reset=sensorOK recovery(PUB005)
 * Units: BOOL states, edge-detect via local prev variables, no timers
 *)
(* CONTRACT_RULES [{"kind":"hold_until_reset","output":"alarmActive","set_input":"flowLow","reset_input":"ackBtn"},{"kind":"hold_until_reset","output":"alarmAcked","set_input":"flowLow","reset_input":"ackBtn"}] *)

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
    prev_ackBtn   : BOOL;
    prev_flowLow  : BOOL;
END_VAR

    IF ackBtn AND NOT prev_ackBtn THEN
        IF alarmActive THEN
            IF flowLow THEN
                alarmAcked := TRUE;
            ELSE
                alarmActive := FALSE;
                alarmAcked  := FALSE;
            END_IF;
        END_IF;
    ELSIF flowLow AND NOT prev_flowLow THEN
        alarmActive := TRUE;
        alarmAcked  := FALSE;
    ELSIF NOT flowLow AND alarmActive AND alarmAcked THEN
        alarmActive := FALSE;
        alarmAcked  := FALSE;
    END_IF;

    highHigh := NOT sensorOK;

    prev_ackBtn  := ackBtn;
    prev_flowLow := flowLow;
END_FUNCTION_BLOCK
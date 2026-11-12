FUNCTION_BLOCK FB
VAR_INPUT
    flowLow: BOOL;
    ackBtn: BOOL;
    sensorOK: BOOL;
END_VAR
VAR_OUTPUT
    alarmActive: BOOL;
    alarmAcked: BOOL;
    highHigh: BOOL;
END_VAR
VAR
    prev_flowLow: BOOL := FALSE;
    prev_ackBtn: BOOL := FALSE;
    prev_alarmActive: BOOL := FALSE;
    prev_alarmAcked: BOOL := FALSE;
    rising_ack: BOOL;
    prev_combined: BOOL;
    prev_triple: BOOL;
    new_alarmActive: BOOL;
    new_alarmAcked: BOOL;
END_VAR

(* ENGINEERING_CONTRACT
   alarmActive: state latch; activates on flowLow TRUE (PUB001-PUB003);
     retains while prior alarmActive TRUE and no ack rising edge and not
     prior (flowLow AND alarmAcked); clears only on ack rising edge when
     flowLow FALSE (PUB003, S6). Same-scan independent of highHigh.
   alarmAcked: state latch; set when alarmActive and either flowLow FALSE,
     ack rising edge, or prior (flowLow AND alarmActive AND alarmAcked);
     clears with alarmActive (PUB002-PUB003, S7).
   highHigh: pure combinational; TRUE exactly when sensorOK FALSE;
     no retention; same-scan (PUB004-PUB005, S3, S5).
   All states updated once per scan; outputs sampled at cycle end.
*)

(* CONTRACT_RULES [] *)

highHigh := NOT sensorOK;

rising_ack := ackBtn AND NOT prev_ackBtn;

prev_combined := prev_flowLow AND prev_alarmAcked;
prev_triple := prev_flowLow AND prev_alarmActive AND prev_alarmAcked;

new_alarmActive := flowLow OR (prev_alarmActive AND NOT rising_ack AND NOT prev_combined);
new_alarmAcked := new_alarmActive AND (NOT flowLow OR rising_ack OR prev_triple);

alarmActive := new_alarmActive;
alarmAcked := new_alarmAcked;

prev_flowLow := flowLow;
prev_ackBtn := ackBtn;
prev_alarmActive := alarmActive;
prev_alarmAcked := alarmAcked;

END_FUNCTION_BLOCK
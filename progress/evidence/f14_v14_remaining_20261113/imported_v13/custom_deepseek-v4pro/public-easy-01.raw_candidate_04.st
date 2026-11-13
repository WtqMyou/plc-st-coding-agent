(*
ENGINEERING_CONTRACT
Pump_Motor: activation=rising edge bottleSensor (PUB001); hold until finishedButton rising edge cycle reset (PUB008); does not stop on later step starts; BOOL latch.
Filling_Valve: activation=rising edge cleaningConfirmButton (PUB002); hold until finishedButton rising (PUB008); BOOL latch.
Capping_Machine: activation=rising edge fillingConfirmButton (PUB003); hold until finishedButton rising (PUB008); BOOL latch.
Packing_Machine: activation=rising edge cappingConfirmButton (PUB004); hold until finishedButton rising (PUB008); BOOL latch.
Completion_Light: activation=rising edge packingConfirmButton (PUB005/PUB006); hold until finishedButton rising (PUB007/PUB008); BOOL latch.
Priority: finishedButton reset overrides same-scan set edges. Inputs are edge-triggered; no interlock between buttons is specified.
*)

(* CONTRACT_RULES [] *)

FUNCTION_BLOCK AutomatedFillingLineControl
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
    pump_latch : BOOL := FALSE;
    fill_latch : BOOL := FALSE;
    cap_latch : BOOL := FALSE;
    pack_latch : BOOL := FALSE;
    light_latch : BOOL := FALSE;

    trigBottle : R_TRIG;
    trigClean : R_TRIG;
    trigFill : R_TRIG;
    trigCap : R_TRIG;
    trigPack : R_TRIG;
    trigFinished : R_TRIG;

    tmp_bottle_edge : BOOL;
    tmp_clean_edge : BOOL;
    tmp_fill_edge : BOOL;
    tmp_cap_edge : BOOL;
    tmp_pack_edge : BOOL;
    tmp_finished_edge : BOOL;
END_VAR

trigBottle(CLK := bottleSensor);
tmp_bottle_edge := trigBottle.Q;

trigClean(CLK := cleaningConfirmButton);
tmp_clean_edge := trigClean.Q;

trigFill(CLK := fillingConfirmButton);
tmp_fill_edge := trigFill.Q;

trigCap(CLK := cappingConfirmButton);
tmp_cap_edge := trigCap.Q;

trigPack(CLK := packingConfirmButton);
tmp_pack_edge := trigPack.Q;

trigFinished(CLK := finishedButton);
tmp_finished_edge := trigFinished.Q;

IF finishedButton THEN
    pump_latch := FALSE;
    fill_latch := FALSE;
    cap_latch := FALSE;
    pack_latch := FALSE;
    light_latch := FALSE;
ELSE
    IF tmp_bottle_edge THEN
        pump_latch := TRUE;
    END_IF;

    IF tmp_clean_edge THEN
        fill_latch := TRUE;
    END_IF;

    IF tmp_fill_edge THEN
        cap_latch := TRUE;
    END_IF;

    IF tmp_cap_edge THEN
        pack_latch := TRUE;
    END_IF;

    IF tmp_pack_edge THEN
        light_latch := TRUE;
    END_IF;
END_IF;

Pump_Motor := pump_latch;
Filling_Valve := fill_latch;
Capping_Machine := cap_latch;
Packing_Machine := pack_latch;
Completion_Light := light_latch;

END_FUNCTION_BLOCK
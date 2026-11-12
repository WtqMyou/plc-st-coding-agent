TYPE ProductionState : (IDLE, TO_WASH, AT_WASH, TO_WEIGHT, AT_WEIGHT, TO_FIRING, AT_FIRING, TO_OUTPUT, AT_OUTPUT, REJECTING) := IDLE;
END_TYPE

(* ENGINEERING_CONTRACT
Manual forward/reverse: Mode=0; active when corresponding button true and other false; simultaneous => both false (PUB002).
Auto forward: active in TO_WASH/TO_WEIGHT/TO_FIRING/TO_OUTPUT; deasserted when target sensor activates; retained while moving (PUB003-PUB005).
Auto stop: AT_WASH/AT_WEIGHT/AT_FIRING/AT_OUTPUT wait for complete signal or removal; no edge detection (PUB003-PUB006).
kick: active when unqualified at weighing station after weightComplete; held until SensorWeight false; manual clears (PUB003).
CompletionLight: active while SensorOutput true in AT_OUTPUT; deasserted on SensorOutput false or manual (PUB006).
firingTemp: computed on qualified weight: 500+(weight-100)*0.5 for weight 100..200; retained through firing/output; cleared otherwise/manual (PUB003).
State: non-retain; starts IDLE; transitions by public sensors/signals; unspecified behavior if sensors overlap or mode changes mid-cycle.
*)
(* CONTRACT_RULES [] *)

FUNCTION_BLOCK ProductionControl
VAR_INPUT
    Mode : BOOL;
    ForwardButton : BOOL;
    ReverseButton : BOOL;
    SensorFeed : BOOL;
    SensorWash : BOOL;
    SensorWeight : BOOL;
    SensorFiring : BOOL;
    SensorOutput : BOOL;
    washComplete : BOOL;
    weightComplete : BOOL;
    weight : REAL;
    firingComplete : BOOL;
END_VAR
VAR_OUTPUT
    MotorForward : BOOL;
    MotorReverse : BOOL;
    kick : BOOL;
    CompletionLight : BOOL;
    firingTemp : REAL;
END_VAR
VAR
    state : ProductionState := ProductionState#IDLE;
    local_temp : REAL := 0.0;
END_VAR

IF Mode THEN
    (* Automatic mode *)
    MotorReverse := FALSE;
    CASE state OF
        ProductionState#IDLE:
            MotorForward := FALSE;
            kick := FALSE;
            firingTemp := 0.0;
            CompletionLight := FALSE;
            IF SensorFeed THEN
                state := ProductionState#TO_WASH;
            END_IF;

        ProductionState#TO_WASH:
            MotorForward := TRUE;
            kick := FALSE;
            firingTemp := 0.0;
            CompletionLight := FALSE;
            IF SensorWash THEN
                MotorForward := FALSE;
                state := ProductionState#AT_WASH;
            END_IF;

        ProductionState#AT_WASH:
            MotorForward := FALSE;
            kick := FALSE;
            firingTemp := 0.0;
            CompletionLight := FALSE;
            IF washComplete THEN
                MotorForward := TRUE;
                state := ProductionState#TO_WEIGHT;
            END_IF;

        ProductionState#TO_WEIGHT:
            MotorForward := TRUE;
            kick := FALSE;
            firingTemp := 0.0;
            CompletionLight := FALSE;
            IF SensorWeight THEN
                MotorForward := FALSE;
                state := ProductionState#AT_WEIGHT;
            END_IF;

        ProductionState#AT_WEIGHT:
            MotorForward := FALSE;
            kick := FALSE;
            firingTemp := 0.0;
            CompletionLight := FALSE;
            IF weightComplete THEN
                IF (weight >= 100.0) AND (weight <= 200.0) THEN
                    local_temp := 500.0 + (weight - 100.0) * 0.5;
                    firingTemp := local_temp;
                    state := ProductionState#TO_FIRING;
                ELSE
                    firingTemp := 0.0;
                    kick := TRUE;
                    state := ProductionState#REJECTING;
                END_IF;
            END_IF;

        ProductionState#REJECTING:
            MotorForward := FALSE;
            kick := TRUE;
            firingTemp := 0.0;
            CompletionLight := FALSE;
            IF NOT SensorWeight THEN
                kick := FALSE;
                state := ProductionState#IDLE;
            END_IF;

        ProductionState#TO_FIRING:
            MotorForward := TRUE;
            kick := FALSE;
            firingTemp := local_temp;
            CompletionLight := FALSE;
            IF SensorFiring THEN
                MotorForward := FALSE;
                state := ProductionState#AT_FIRING;
            END_IF;

        ProductionState#AT_FIRING:
            MotorForward := FALSE;
            kick := FALSE;
            firingTemp := local_temp;
            CompletionLight := FALSE;
            IF firingComplete THEN
                MotorForward := TRUE;
                state := ProductionState#TO_OUTPUT;
            END_IF;

        ProductionState#TO_OUTPUT:
            MotorForward := TRUE;
            kick := FALSE;
            firingTemp := local_temp;
            CompletionLight := FALSE;
            IF SensorOutput THEN
                MotorForward := FALSE;
                state := ProductionState#AT_OUTPUT;
            END_IF;

        ProductionState#AT_OUTPUT:
            MotorForward := FALSE;
            kick := FALSE;
            firingTemp := local_temp;
            CompletionLight := TRUE;
            IF NOT SensorOutput THEN
                CompletionLight := FALSE;
                state := ProductionState#IDLE;
            END_IF;
    END_CASE;
ELSE
    (* Manual mode *)
    MotorForward := FALSE;
    MotorReverse := FALSE;
    kick := FALSE;
    CompletionLight := FALSE;
    firingTemp := 0.0;

    IF ForwardButton AND NOT ReverseButton THEN
        MotorForward := TRUE;
        MotorReverse := FALSE;
    ELSIF ReverseButton AND NOT ForwardButton THEN
        MotorForward := FALSE;
        MotorReverse := TRUE;
    ELSE
        MotorForward := FALSE;
        MotorReverse := FALSE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
TYPE ProductionState : (IDLE, TO_WASH, AT_WASH, TO_WEIGHT, AT_WEIGHT, TO_FIRING, AT_FIRING, TO_OUTPUT, AT_OUTPUT, REJECTING) := IDLE;
END_TYPE;

(* ENGINEERING_CONTRACT
Manual forward/reverse: Mode=0; active when corresponding button true and other false; simultaneous => both false (PUB002).
Auto forward: active in TO_WASH/TO_WEIGHT/TO_FIRING/TO_OUTPUT; deasserted when target sensor activates; retained while moving (PUB003-PUB005).
Auto stop: AT_WASH/AT_WEIGHT/AT_FIRING/AT_OUTPUT wait for complete signal or removal; no edge detection (PUB003-PUB006).
kick: active when unqualified at weighing station after weightComplete; held until SensorWeight false; manual clears (PUB003).
CompletionLight: active while SensorOutput true in AT_OUTPUT; deasserted on SensorOutput false or manual (PUB006).
firingTemp: computed on qualified weight: 500+(weight-100)*0.5 for weight 100..200; retained through firing/output; cleared otherwise/manual (PUB003).
State: non-retain; starts IDLE; transitions by public sensors/signals; unspecified behavior if sensors overlap or mode changes mid-cycle.
Same-scan: outputs are recomputed after every state transition in the same invocation.
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
    state : ProductionState := ProductionState.IDLE;
    local_temp : REAL := 0.0;
END_VAR

IF Mode THEN
    (* Automatic mode *)
    MotorReverse := FALSE;

    (* State transition logic *)
    CASE state OF
        IDLE:
            IF SensorFeed THEN
                state := ProductionState.TO_WASH;
            END_IF;

        TO_WASH:
            IF SensorWash THEN
                state := ProductionState.AT_WASH;
            END_IF;

        AT_WASH:
            IF washComplete THEN
                state := ProductionState.TO_WEIGHT;
            END_IF;

        TO_WEIGHT:
            IF SensorWeight THEN
                state := ProductionState.AT_WEIGHT;
            END_IF;

        AT_WEIGHT:
            IF weightComplete THEN
                IF (weight >= 100.0) AND (weight <= 200.0) THEN
                    local_temp := 500.0 + (weight - 100.0) * 0.5;
                    state := ProductionState.TO_FIRING;
                ELSE
                    state := ProductionState.REJECTING;
                END_IF;
            END_IF;

        REJECTING:
            IF NOT SensorWeight THEN
                state := ProductionState.IDLE;
            END_IF;

        TO_FIRING:
            IF SensorFiring THEN
                state := ProductionState.AT_FIRING;
            END_IF;

        AT_FIRING:
            IF firingComplete THEN
                state := ProductionState.TO_OUTPUT;
            END_IF;

        TO_OUTPUT:
            IF SensorOutput THEN
                state := ProductionState.AT_OUTPUT;
            END_IF;

        AT_OUTPUT:
            IF NOT SensorOutput THEN
                state := ProductionState.IDLE;
            END_IF;
    END_CASE;

    (* Compute outputs from current state after transitions *)
    MotorForward := FALSE;
    kick := FALSE;
    CompletionLight := FALSE;
    firingTemp := 0.0;

    CASE state OF
        TO_WASH, TO_WEIGHT, TO_FIRING, TO_OUTPUT:
            MotorForward := TRUE;
    END_CASE;

    IF (state = AT_OUTPUT) AND SensorOutput THEN
        CompletionLight := TRUE;
    END_IF;

    IF (state = REJECTING) AND SensorWeight THEN
        kick := TRUE;
    END_IF;

    IF (state = TO_FIRING) OR (state = AT_FIRING) OR (state = TO_OUTPUT) OR (state = AT_OUTPUT) THEN
        firingTemp := local_temp;
    END_IF;

ELSE
    (* Manual mode *)
    MotorForward := FALSE;
    MotorReverse := FALSE;
    kick := FALSE;
    CompletionLight := FALSE;
    firingTemp := 0.0;

    IF ForwardButton AND NOT ReverseButton THEN
        MotorForward := TRUE;
    ELSIF ReverseButton AND NOT ForwardButton THEN
        MotorReverse := TRUE;
    ELSE
        MotorForward := FALSE;
        MotorReverse := FALSE;
    END_IF;
END_IF;

END_FUNCTION_BLOCK
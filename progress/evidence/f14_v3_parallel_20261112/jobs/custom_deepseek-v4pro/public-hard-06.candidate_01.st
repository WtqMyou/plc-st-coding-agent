TYPE T_PRODUCTION_STATE :
(
    IDLE,
    MOVING_FEED_TO_WASH,
    AT_WASH,
    MOVING_WASH_TO_WEIGHT,
    AT_WEIGHT_WAIT,
    AT_WEIGHT_REJECT,
    MOVING_WEIGHT_TO_FIRING,
    AT_FIRING,
    MOVING_FIRING_TO_OUTPUT,
    AT_OUTPUT
);
END_TYPE;

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
    currentState : T_PRODUCTION_STATE := IDLE;
END_VAR
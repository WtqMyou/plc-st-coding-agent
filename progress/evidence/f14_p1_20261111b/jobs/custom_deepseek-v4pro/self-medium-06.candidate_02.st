FUNCTION_BLOCK FB
VAR_INPUT
    enable : BOOL;
    resetBtn : BOOL;
    sensorValid : BOOL;
    setpoint : REAL;
    temperature : REAL;
    scanSeconds : REAL;
    bias : REAL;
END_VAR
VAR_OUTPUT
    power : REAL;
    correction : REAL;
    fault : BOOL;
END_VAR
VAR
    ePrev : REAL;
    histValid : BOOL;
    lastResetBtn : BOOL;
END_VAR
VAR_TEMP
    e : REAL;
    de : REAL;
    x : REAL;
    y : REAL;
    resetRising : BOOL;
    tempPower : REAL;
END_VAR

BEGIN
    -- Compute error
    e := setpoint - temperature;
    
    -- Compute fault status
    fault := NOT sensorValid OR (scanSeconds <= 0.0) OR (scanSeconds > 10.0);
    
    -- Detect rising edge of reset button
    resetRising := resetBtn AND NOT lastResetBtn;
    
    IF (NOT enable OR fault OR resetRising) THEN
        -- Fault, disabled, or reset rising edge:
        -- Output zero and clear history
        power := 0.0;
        correction := 0.0;
        ePrev := 0.0;
        histValid := FALSE;
    ELSE
        -- Normal fuzzy calculation
        IF histValid THEN
            de := (e - ePrev) / scanSeconds;
        ELSE
            de := 0.0;  -- First cycle after start/reset/fault recovery
        END_IF;
        
        -- Clamp x to [-1, 1]
        x := e / 10.0;
        IF x < -1.0 THEN
            x := -1.0;
        ELSIF x > 1.0 THEN
            x := 1.0;
        END_IF;
        
        -- Clamp y to [-1, 1]
        y := de / 2.0;
        IF y < -1.0 THEN
            y := -1.0;
        ELSIF y > 1.0 THEN
            y := 1.0;
        END_IF;
        
        -- Nine-rule centroid equivalent: 20*x + 10*y
        correction := 20.0 * x + 10.0 * y;
        
        -- Clamp power to [0, 100]
        tempPower := bias + correction;
        IF tempPower < 0.0 THEN
            power := 0.0;
        ELSIF tempPower > 100.0 THEN
            power := 100.0;
        ELSE
            power := tempPower;
        END_IF;
        
        -- Update history
        ePrev := e;
        histValid := TRUE;
    END_IF;
    
    -- Store current reset button state for next cycle edge detection
    lastResetBtn := resetBtn;
END_FUNCTION_BLOCK
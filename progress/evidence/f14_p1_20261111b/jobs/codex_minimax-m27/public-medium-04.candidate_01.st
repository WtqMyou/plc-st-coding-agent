FUNCTION_BLOCK FB_TemperatureControl
VAR_INPUT
    TemperatureSensorInput : REAL;
    SetTemperature         : REAL;
END_VAR

VAR_OUTPUT
    CurrentTemperature : REAL;
    SetTempDisplay     : REAL;
    HeaterStatus       : BOOL;
    OverheatProtection : BOOL;
    HeaterOutput       : BOOL;
END_VAR

VAR
    // Internal variables
    rCurrentTemperature  : REAL := 0.0;
    rSetTemperature      : REAL := 0.0;
    bHeaterOn            : BOOL := FALSE;
    bOverheatProtection  : BOOL := FALSE;
    bSensorFault         : BOOL := FALSE;
    
    // Timer for heater on-time monitoring
    HeaterOnTimer        : TON;
    // Timer for overheat protection cooldown
    OverheatCooldownTimer: TON;
    
    // Constants
    MAX_HEATER_ON_TIME   : TIME := T#5S;
    OVERHEAT_COOLDOWN    : TIME := T#3S;
    MIN_SENSOR_VALUE     : REAL := 0.0;
    MAX_SENSOR_VALUE     : REAL := 100.0;
END_VAR

//============================================================================
// Temperature Logic Control - Main Program
//============================================================================

// Update internal temperature values from inputs
rCurrentTemperature := TemperatureSensorInput;
rSetTemperature     := SetTemperature;

// Update output displays
CurrentTemperature := rCurrentTemperature;
SetTempDisplay     := rSetTemperature;
HeaterStatus       := bHeaterOn;
OverheatProtection := bOverheatProtection;

//============================================================================
// Sensor Fault Detection
// If temperature is outside valid range (0-100), trigger sensor fault
//============================================================================
bSensorFault := (rCurrentTemperature < MIN_SENSOR_VALUE) OR 
                (rCurrentTemperature > MAX_SENSOR_VALUE);

IF bSensorFault THEN
    // Sensor fault: turn off heater immediately
    bHeaterOn          := FALSE;
    HeaterOutput       := FALSE;
    bOverheatProtection := TRUE;
    
    // Reset heater on timer when heater is off
    HeaterOnTimer(IN := FALSE);
    
    // Return early - no temperature control during sensor fault
    RETURN;
END_IF;

//============================================================================
// Overheat Protection Check
// If protection is active, must wait for cooldown period before reset
//============================================================================
IF bOverheatProtection THEN
    // Start or continue cooldown timer
    OverheatCooldownTimer(IN := TRUE, PT := OVERHEAT_COOLDOWN);
    
    // Check if cooldown period has elapsed
    IF OverheatCooldownTimer.Q THEN
        // Cooldown complete - reset overheat protection
        bOverheatProtection        := FALSE;
        OverheatCooldownTimer(IN := FALSE);
    END_IF;
    
    // Keep heater off during overheat protection
    bHeaterOn := FALSE;
    HeaterOutput := FALSE;
    
    // Return early - no temperature control during overheat protection
    RETURN;
ELSE
    // Reset cooldown timer when protection is not active
    OverheatCooldownTimer(IN := FALSE);
END_IF;

//============================================================================
// Temperature Control Logic
// Compare actual temperature with set temperature
//============================================================================
IF rCurrentTemperature < rSetTemperature THEN
    // Temperature below setpoint - turn ON heater
    bHeaterOn := TRUE;
ELSIF rCurrentTemperature >= rSetTemperature THEN
    // Temperature at or above setpoint - turn OFF heater
    bHeaterOn := FALSE;
END_IF;

//============================================================================
// Heater Output Control
//============================================================================
HeaterOutput := bHeaterOn;

//============================================================================
// Heater On-Time Monitoring for Overheat Protection
// If heater runs continuously for more than 5 seconds, trigger protection
//============================================================================
IF bHeaterOn THEN
    // Start or continue the heater on-time timer
    HeaterOnTimer(IN := TRUE, PT := MAX_HEATER_ON_TIME);
    
    // Check if timer has elapsed (heater on for too long)
    IF HeaterOnTimer.Q THEN
        // Overheat protection triggered
        bHeaterOn           := FALSE;
        bOverheatProtection := TRUE;
        HeaterOutput        := FALSE;
        
        // Reset heater on timer
        HeaterOnTimer(IN := FALSE);
    END_IF;
ELSE
    // Heater is off - reset the timer
    HeaterOnTimer(IN := FALSE);
END_IF;

END_FUNCTION_BLOCK
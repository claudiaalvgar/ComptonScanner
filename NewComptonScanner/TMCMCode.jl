// ========================================================================
// TMCM-3351 SYNCHRONOUS 3-AXIS VERTICAL LIFT SCRIPT
// ========================================================================
// GLOBAL PARAMETERS (Bank 2) INTERFACE:
// GP 0:  Target Position (Microsteps)
// GP 1:  Target Speed (Velocity units)
// GP 10: State Machine Command Register
//         0 = Idle / Task Complete
//         1 = Execute Synchronous Move
//         2 = Execute Synchronous Homing
//        99 = Error / Jam Detected (System Halted)
// ========================================================================

// --- INITIALIZATION ---
    SGP 10, 2, 0            // Set State to 0 (Idle) on controller boot

// ========================================================================
// MAIN STATE MACHINE LOOP
// ========================================================================
MainLoop:
    GGP 10, 2               // Read the State Machine register (GP 10)
    
    COMP 1                  // If Julia wrote '1', execute movement
    JC EQ, StartMove
    
    COMP 2                  // If Julia wrote '2', execute homing
    JC EQ, StartHome

    COMP 3                  // Execute Closed-Loop Initialization
    JC EQ, StartInit

    COMP 4                  // Execute Power ON
    JC EQ, PowerOn

    COMP 5                  // Execute Power OFF
    JC EQ, PowerOff
    
    JA MainLoop             // Otherwise, loop infinitely and wait

// ========================================================================
// 1. SYNCHRONOUS MOVEMENT ROUTINE
// ========================================================================
StartMove:
    // Load Speed (GP 1) into Accumulator and apply to all axes (AP 4)
    GGP 1, 2
    AAP 4, 0                // Set Axis 0 Max Positioning Speed
    AAP 4, 1                // Set Axis 1 Max Positioning Speed
    AAP 4, 2                // Set Axis 2 Max Positioning Speed

    // Load Target Pos (GP 0) into Accumulator and apply to all axes (AP 0)
    // Note: Writing to AP 0 automatically triggers the trajectory generator
    GGP 0, 2
    AAP 0, 0                // Start Axis 0
    AAP 0, 1                // Start Axis 1
    AAP 0, 2                // Start Axis 2

WaitMove:
    // --- Jam Protection (Monitor AP 212: Actual Position Error) ---
    // Axis 0
    GAP 212, 0              
    COMP 50                 // Positive error threshold (Tune this!)
    JC GT, ErrorHalt
    COMP -50                // Negative error threshold
    JC LT, ErrorHalt
    
    // Axis 1
    GAP 212, 1
    COMP 50
    JC GT, ErrorHalt
    COMP -50
    JC LT, ErrorHalt

    // Axis 2
    GAP 212, 2
    COMP 50
    JC GT, ErrorHalt
    COMP -50
    JC LT, ErrorHalt

    // --- Completion Check (Monitor AP 8: Position Reached Flag) ---
    GAP 8, 0                // Check Axis 0
    COMP 1                  // 1 = Target Reached
    JC NE, WaitMove         // If not reached, loop back and keep monitoring
    
    GAP 8, 1                // Check Axis 1
    COMP 1
    JC NE, WaitMove
    
    GAP 8, 2                // Check Axis 2
    COMP 1
    JC NE, WaitMove

    // --- Move Successful ---
    SGP 10, 2, 0            // Reset State to 0 (Idle/Done)
    JA MainLoop

// ========================================================================
// 2. SYNCHRONOUS HOMING (Master Axis 0 Strategy)
// ========================================================================
StartHome:
    // Apply Homing Search Speed (GP 1) to all axes
    GGP 1, 2
    AAP 4, 0
    AAP 4, 1
    AAP 4, 2

    // Command a massive negative absolute move to simulate continuous 
    // downward rotation. -2,000,000,000 is safely within 32-bit limits.
    SAP 0, 0, -2000000000
    SAP 0, 1, -2000000000
    SAP 0, 2, -2000000000

WaitHome:
    // --- Jam Protection (During Homing) ---
    GAP 212, 0
    COMP 50
    JC GT, ErrorHalt
    COMP -50
    JC LT, ErrorHalt
    GAP 212, 1
    COMP 50
    JC GT, ErrorHalt
    COMP -50
    JC LT, ErrorHalt
    GAP 212, 2
    COMP 50
    JC GT, ErrorHalt
    COMP -50
    JC LT, ErrorHalt

    // --- Monitor Left Limit Switch of Axis 0 (AP 11) ---
    GAP 11, 0               // Get Left Limit Switch Status
    COMP 1                  // 1 = Switch is pressed/active
    JC NE, WaitHome         // If not pressed, keep moving and checking

    // --- Switch Hit! ---
    // Instantly halt all axes to maintain synchronization
    MST 0
    MST 1
    MST 2

    // Set the internal step counters to 0
    SAP 1, 0, 0             // Set Actual Position Axis 0 to 0
    SAP 1, 1, 0             // Set Actual Position Axis 1 to 0
    SAP 1, 2, 0             // Set Actual Position Axis 2 to 0
    
    // Set the encoder counters to 0
    SAP 209, 0, 0           // Set Encoder Position Axis 0 to 0
    SAP 209, 1, 0           // Set Encoder Position Axis 1 to 0
    SAP 209, 2, 0           // Set Encoder Position Axis 2 to 0

    // --- Homing Successful ---
    SGP 10, 2, 0            // Reset State to 0 (Idle/Done)
    JA MainLoop

// ========================================================================
// 3. CLOSED-LOOP INITIALIZATION ROUTINE (Run once after power-up)
// ========================================================================
StartInit:
    // 1. Disable Closed-Loop temporarily so the search can run
    SAP 129, 0, 0           // AP 129 = Closed Loop Enable
    SAP 129, 1, 0
    SAP 129, 2, 0

    // (Note: Julia MUST have already turned the motor current AP 6/7 on 
    // before calling this state, or the motors cannot move to align!)

    // 2. Trigger the Commutation Search for all axes simultaneously
    SAP 130, 0, 1           // AP 130 = Closed Loop Calibration
    SAP 130, 1, 1
    SAP 130, 2, 1


WaitInit:
    // 3. Monitor the search status. The controller automatically sets AP 130 
    // back to 0 when the motor has successfully aligned with the encoder.
    GAP 130, 0
    COMP 0
    JC NE, WaitInit
    
    GAP 130, 1
    COMP 0
    JC NE, WaitInit

    GAP 130, 2
    COMP 0
    JC NE, WaitInit

    // 4. Re-enable Closed-Loop control now that calibration is complete
    SAP 129, 0, 1
    SAP 129, 1, 1
    SAP 129, 2, 1

    // 5. Initialization Successful
    SGP 10, 2, 0            // Reset State to 0 (Idle/Done)
    JA MainLoop


// ========================================================================
// 4. POWER ON ROUTINE
// ========================================================================
PowerOn:
	// 1. Anti-Tick Sync: Read the current encoder resting positions and 
    	//    overwrite the target positions so the closed-loop doesn't jump.
    	GAP 209, 0              // Read Axis 0 Encoder
    	AAP 0, 0                // Set as Axis 0 Target Position
    	GAP 209, 1              
    	AAP 0, 1                
    	GAP 209, 2              
    	AAP 0, 2     

	// 2. Apply Run and Standby Currents 
  	//    (Replace 255 and 127 with your actual tuned 0-255 values)
    	SAP 6, 0, 255
    	SAP 6, 1, 255
    	SAP 6, 2, 255
    	SAP 7, 0, 127
    	SAP 7, 1, 127
    	SAP 7, 2, 127

	// 3. Wait for the magnetic field and closed-loop PID to stabilize.
    	//    WAIT TICKS uses 10ms increments. 5 ticks = 50 milliseconds.
    	WAIT TICKS, 0, 5

    	// 4. Power On Complete
    	SGP 10, 2, 0            // Reset State to 0 (Idle/Ready)
    	JA MainLoop


// ========================================================================
// 5. POWER OFF ROUTINE (Measurement Mode)
// ========================================================================
PowerOff:
	// Drop all currents to 0. 
    	// The H-bridges go dark, the board goes silent, gravity takes over.
    	SAP 6, 0, 0
    	SAP 6, 1, 0
    	SAP 6, 2, 0
    	SAP 7, 0, 0
    	SAP 7, 1, 0
    	SAP 7, 2, 0

    	SGP 10, 2, 0            // Reset State to 0 (Idle/Ready)
    	JA MainLoop
// ========================================================================
// EMERGENCY HALT ROUTINE
// ========================================================================
ErrorHalt:
    MST 0                   // Motor STop Axis 0
    MST 1                   // Motor STop Axis 1
    MST 2                   // Motor STop Axis 2
    
    SGP 10, 2, 99           // Set State to 99 to alert Julia of the jam
    JA MainLoop             // Wait for Julia to clear the error state













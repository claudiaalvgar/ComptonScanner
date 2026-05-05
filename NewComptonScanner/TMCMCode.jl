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
//         3 = Init
//         4 = Power ON
//         5 = Power OFF
//        99 = Error / Jam Detected (System Halted)


//Element	Role
//GP 0	data (position)
//GP 1	data (speed)
//GGP	reads data
//AAP	applies data
//SGP	write global parameter (set state)
//GGP	read global parameter
//SAP	set axis parameter
//GAP	get axis parameter
//COMP + JC	decision logic (if/while)


// ========================================================================

// --- INITIALIZATION ---
    SGP 10, 2, 0            // Ensure controller starts in a defined communication/state mode

// ========================================================================
// MAIN STATE MACHINE LOOP
// ========================================================================
MainLoop:
    GGP 10, 2               // Read the State Machine register (GP 10). The controller is waiting for an external system (Julia) to write a number into GP 10 bank 2
    
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

    COMP 6
    JC EQ, DisableClosedLoop

    COMP 99
    JC EQ, ErrorState
        
    COMP 999
    JC EQ, EndLoop          // emergency escape

    WAIT TICKS, 0, 1
    
    JA MainLoop             // Otherwise, loop infinitely and wait

// ========================================================================
// 0. EXIT
// ========================================================================
EndLoop:
    MST 0
    MST 1
    MST 2
    STOP                     // Stops execution of the TMCL program

// ========================================================================
// EMERGENCY HALT ROUTINE
// ========================================================================
ErrorHalt:
    MST 0                   // Motor STop Axis 0
    MST 1                   // Motor STop Axis 1
    MST 2                   // Motor STop Axis 2

    CALL CL_Disable
        
    SGP 10, 2, 99           // Set State to 99 to alert Julia of the jam
    JA ErrorState           // go directly into error handling state

ErrorState:
    GGP 10, 2
    COMP 0
    JC NE, ErrorState

    CALL CL_Disable

    JA MainLoop
// ========================================================================
// 1. SYNCHRONOUS MOVEMENT ROUTINE
// ========================================================================
StartMove:
    SGP 10, 2, 0            // Reset State to 0 (Idle/Done) clear command immediately
    // Load Speed (GP 1) into Accumulator and apply to all axes (AP 4)
    GGP 4, 2
    AAP 4, 0                // Set Axis 0 Max Positioning Speed
    AAP 4, 1                // Set Axis 1 Max Positioning Speed
    AAP 4, 2                // Set Axis 2 Max Positioning Speed

    // Load Target Pos (GP 0) into Accumulator and apply to all axes (AP 0)
    // Note: Writing to AP 0 automatically triggers the trajectory generator
    GGP 0, 2
    AAP 0, 0                // Set target position and Move Axis 0 towards it
    AAP 0, 1                // Move Axis 1
    AAP 0, 2                // Move Axis 2

WaitMove:
    // Axis 0
    GAP 1, 0
    GAP 209, 0
    CALC SUB
    COMP 1000              // tune this!
    JC GT, ErrorHalt
    COMP -1000
    JC LT, ErrorHalt

    // Axis 1
    GAP 1, 1
    GAP 209, 1
    CALC SUB
    COMP 1000
    JC GT, ErrorHalt
    COMP -1000
    JC LT, ErrorHalt

    // Axis 2
    GAP 1, 2
    GAP 209, 2
    CALC SUB
    COMP 1000
    JC GT, ErrorHalt
    COMP -1000
    JC LT, ErrorHalt

    // ============================================================
    // POSITION REACHED CHECK
    // ============================================================

    GAP 8, 0
    COMP 1
    JC NE, WaitMove

    GAP 8, 1
    COMP 1
    JC NE, WaitMove

    GAP 8, 2
    COMP 1
    JC NE, WaitMove
        
    WAIT TICKS, 0, 1
    JA MainLoop

// ========================================================================
// 2. SYNCHRONOUS HOMING (Master Axis 0 Strategy) a “reference search” (homing)
// ========================================================================
StartHome:
    // Apply Homing Search Speed (GP 1) to all axes
    GGP 4, 2
    AAP 4, 0
    AAP 4, 1
    AAP 4, 2

    // --- Move DOWN toward home ---
    ROR 0
    ROR 1
    ROR 2

    JA WaitHome

WaitHome:
    // ================================================================        
    // --- Jam Protection (During Homing) ---
    // deviation = AP1 - AP209
    // ================================================================

    // Axis 0
    GAP 1, 0          // actual position
    GAP 209, 0        // encoder position
    CALC SUB
    COMP 1000         // threshold (tune this!)
    JC GT, ErrorHalt
    COMP -1000
    JC LT, ErrorHalt

    // Axis 1
    GAP 1, 1
    GAP 209, 1
    CALC SUB
    COMP 1000
    JC GT, ErrorHalt
    COMP -1000
    JC LT, ErrorHalt

    // Axis 2
    GAP 1, 2
    GAP 209, 2
    CALC SUB
    COMP 1000
    JC GT, ErrorHalt
    COMP -1000
    JC LT, ErrorHalt

    // --- Monitor Left Limit Switch of Axis 0 ---
    GAP 9, 0                // Move until dedicated reference sensor is hit
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
    WAIT TICKS, 0, 1
    SGP 10, 2, 0            // Reset State to 0 (Idle/Done)
    JA MainLoop

// ========================================================================
// 3. CLOSED-LOOP INITIALIZATION ROUTINE (Run once after power-up)
// ========================================================================
StartInit:
    
    SAP 108,0,300000
    SAP 108,1,300000
    SAP 108,2,300000    
        
    SAP 109,0,600000
    SAP 109,1,600000
    SAP 109,2,600000

    SAP 110,0,255
    SAP 110,1,255
    SAP 110,2,255    
        
    SAP 111,0,255
    SAP 111,1,255
    SAP 111,2,255
        
    SAP 113,0,50
    SAP 113,1,50
    SAP 113,2,50

    SAP 114,0,240
    SAP 114,1,240
    SAP 114,2,240    

    SAP 126,0,25
    SAP 126,1,25
    SAP 126,2,25

    SAP 125,0,100
    SAP 125,1,100
    SAP 125,2,100

    SAP 134,0,100
    SAP 134,1,100
    SAP 134,2,100
        
    SAP 120,0,1000
    SAP 120,1,1000
    SAP 120,2,1000

    SAP 121,0,10000
    SAP 121,1,10000
    SAP 121,2,10000
        
    SAP 115,0,3000
    SAP 115,1,3000
    SAP 115,2,3000

    SAP 116,0,20
    SAP 116,1,20
    SAP 116,2,20

    SAP 117,0,10
    SAP 117,1,10
    SAP 117,2,10
        
    SAP 118,0,0
    SAP 118,1,0
    SAP 118,2,0

    SAP 119,0,100000
    SAP 119,1,100000
    SAP 119,2,100000

    SAP 124,0,65536
    SAP 124,1,65536
    SAP 124,2,65536

    SAP 212,0,1000
    SAP 212,1,1000
    SAP 212,2,1000
    
    SAP 213,0,30000
    SAP 213,1,30000
    SAP 213,2,30000

    // ========================================================================
    // STEP 1: DISABLE CLOSED-LOOP
    // ========================================================================
    SAP 129,0,0
    SAP 129,1,0
    SAP 129,2,0

    // ========================================================================
    // STEP 2: ANTI-JUMP SYNCHRONIZATION
    // Align: encoder = actual = target
    // ========================================================================

    // Axis 0
    GAP 209,0
    AAP 0,0

    // Axis 1
    GAP 209,1
    AAP 0,1

    // Axis 2
    GAP 209,2
    AAP 0,2

 
    // Small stabilization delay
    WAIT TICKS,0,10

    // ========================================================================
    // STEP 3: ENABLE CLOSED-LOOP
    // ========================================================================
    SAP 129,0,1
    SAP 129,1,1
    SAP 129,2,1

    // ========================================================================
    // STEP 4: WAIT FOR CLOSED-LOOP INITIALIZATION (REQUIRED)
    // ========================================================================

WaitInit:

    GAP 133,0
    COMP 0
    JC ZE,WaitInit

    GAP 133,1
    COMP 0
    JC ZE,WaitInit

    GAP 133,2
    COMP 0
    JC ZE,WaitInit

    // ========================================================================
    // STEP 5: MOTION PARAMETERS
    // ========================================================================
    //SAP 4,0,51200
    //SAP 5,0,51200
    //SAP 17,0,51200

    //SAP 4,1,51200
    //SAP 5,1,51200
    //SAP 17,1,51200

    //SAP 4,2,51200
    //SAP 5,2,51200
    //SAP 17,2,51200

    // ========================================================================
    // STEP 6: READY SIGNAL
    // ========================================================================
    SGP 10,2,0
    WAIT TICKS, 0, 1
    JA MainLoop

   
// ========================================================================
// 4. POWER ON ROUTINE
// ========================================================================
PowerOn:

    // 1. Set encoder resolution FIRST
    SAP 210, 0, 2000
    SAP 210, 1, 2000
    SAP 210, 2, 2000

    // 2. Apply currents
    SAP 6, 0, 64
    SAP 6, 1, 64
    SAP 6, 2, 64

    SAP 7, 0, 8
    SAP 7, 1, 8
    SAP 7, 2, 8

    // 3. Let motor stabilize
    WAIT TICKS, 0, 10   // 100 ms (safer than 50)

    // 4. Sync encoder → target position
    GAP 209, 0
    AAP 0, 0

    GAP 209, 1
    AAP 0, 1

    GAP 209, 2
    AAP 0, 2

    // 5. Optional: small delay after sync
    WAIT TICKS, 0, 5

    // 6. Ready state
    SGP 10, 2, 0
    JA MainLoop

// ========================================================================
// DISABLE CLOSED LOOP ROUTINE
// ========================================================================

CL_Disable:

    // ====================================================================
    // STEP 1: CHECK IF CLOSED LOOP IS ENABLED
    // ====================================================================

    GAP 129,0
    COMP 1
    JC NE,CL_Disable0
    JA CL_Check1

CL_Disable0:
    SAP 129,0,0

CL_Check1:
    GAP 129,1
    COMP 1
    JC NE,CL_Disable1
    JA CL_Check2

CL_Disable1:
    SAP 129,1,0

CL_Check2:
    GAP 129,2
    COMP 1
    JC NE,CL_Disable2
    JA CL_Wait

CL_Disable2:
    SAP 129,2,0


    // ====================================================================
    // STEP 2: WAIT UNTIL CLOSED LOOP IS FULLY DISENGAGED
    // ====================================================================

CL_Wait:

WaitLoop:
    GAP 133,0
    COMP 0
    JC NE,WaitLoop

    GAP 133,1
    COMP 0
    JC NE,WaitLoop

    GAP 133,2
    COMP 0
    JC NE,WaitLoop

    WAIT TICKS,0,1

    RET

// ========================================================================
// 5. POWER OFF ROUTINE
// ========================================================================

PowerOff:

    // ====================================================================
    // STEP 1: SAFELY DISABLE CLOSED LOOP
    // ====================================================================

    CALL CL_Disable


    // ====================================================================
    // STEP 2: DROP ALL CURRENTS TO ZERO
    // ====================================================================

    SAP 6, 0, 0
    SAP 6, 1, 0
    SAP 6, 2, 0

    SAP 7, 0, 0
    SAP 7, 1, 0
    SAP 7, 2, 0


    // ====================================================================
    // STEP 3: RESET STATE MACHINE
    // ====================================================================

    SGP 10, 2, 0


    // ====================================================================
    // STEP 4: RETURN TO MAIN LOOP
    // ====================================================================

    JA MainLoop

// ========================================================================
// 6. DISABLE CLOSED LOOP
// ========================================================================

DisableClosedLoop:
   CALL CL_Disable
   SGP 10, 2, 0
   JA MainLoop

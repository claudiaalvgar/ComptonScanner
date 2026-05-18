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
// --- VARIABLES ---
// ========================================================================
Target_Pos = 0
Actual_Pos = 1
Target_Speed = 2
Actual_Speed = 3
Max_Speed = 4
Max_Acceleration = 5
Max_Current = 6
Sandby_Current = 7
TMCM_Command = 10
Max_Deceleration = 17
CLgamma_Vmin = 108
CLgamma_Vmax = 109
CL_Maxgamma = 110
CL_Beta = 111
CL_Currentmin = 113
CL_Currentmax = 114
CL_Correction_VelocityP = 115
CL_Correction_VelocityI = 116
CL_Correction_VelocityI_Clipping = 117
CL_Correction_VelocityDV_Clock = 118
CL_Correction_VelocityDV_Clipping = 119
CL_Upscale_Delay = 120
CL_Downscale_Delay = 121
CL_Correction_Pos = 124
CLmax_Correction_Tolerance = 125
CL_Startup = 126
Pos_Window = 134
Encoder_Pos = 209
Encoder_Resolution = 210
Max_Encoder_Deviation = 212
Max_velocity_Deviation = 213

// ========================================================================
// --- INITIALIZATION --- SOME OF THEM INITIALISED IN JULIA
// ========================================================================
SGP Max_Acceleration, 2, 51200
SGP Max_Current, 2, 25
SGP Sandby_Current, 2, 8
SGP TMCM_Command, 2, 0  // Ensure controller starts in a defined communication/state mode
SGP Max_Deceleration, 2, 51200
SGP CLgamma_Vmin, 2, 300000
SGP CLgamma_Vmax, 2, 600000
SGP CL_Maxgamma, 2, 255
SGP CL_Beta, 2, 255
SGP CL_Currentmin, 2, 50
SGP CL_Currentmax, 2, 240
SGP CL_Correction_VelocityP, 2, 3000
SGP CL_Correction_VelocityI, 2, 20
SGP CL_Correction_VelocityI_Clipping, 2, 10
SGP CL_Correction_VelocityDV_Clock, 2, 0
SGP CL_Correction_VelocityDV_Clipping, 2, 100000
SGP CL_Upscale_Delay, 2, 1000
SGP CL_Downscale_Delay, 2, 10000
SGP CL_Correction_Pos, 65536
SGP CLmax_Correction_Tolerance, 2, 100
SGP CL_Startup, 2, 25
SGP Pos_Window, 2, 100
SGP Encoder_Resolution, 2, 2000
SGP Max_Encoder_Deviation, 2, 1000
SGP Max_Velocity_Deviation, 2, 30000

// SET THIS FROM JULIA
SGP Target_Pos, 2, 100000
SGP Max_Speed, 2, 51200

// ========================================================================
// MAIN STATE MACHINE LOOP
// ========================================================================
MainLoop:
    GGP TMCM_Command, 2      // Read the State Machine register (GP 10). The controller is waiting for an external system (Julia) to write a number into GP 10 bank 2
    
    COMP 1                  // If Julia wrote '1', power on device
    JC EQ, PowerOn
    
    COMP 2
    JC EQ, StartInit

    COMP 3
    JC EQ, DisableClosedLoop

    COMP 4
    JC EQ, EnableClosedLoop

    COMP 5
    JC EQ, StartHome

    COMP 6
    JC EQ, StartMove

    COMP 7
    JC EQ, PowerOff

    COMP 99
    JC EQ, ErrorState
        
    COMP 999
    JC EQ, EndLoop

    WAIT TICKS, 0, 1
    
    JA MainLoop             // Otherwise, loop infinitely and wait

// ========================================================================
// 1. POWER ON
// ========================================================================
PowerOn:

    GGP Encoder_Resolution, 2
    AAP 210, 0
    AAP 210, 1
    AAP 210, 2
        
    GGP Max_Speed, 2 
    AAP 4,0
    AAP 4,1
    AAP 4,2

    GGP Max_Acceleration, 2
    AAP 5,0
    AAP 5,1
    AAP 5,2

    GGP Max_Deceleration, 2
    AAP 17,0
    AAP 17,1
    AAP 17,2

    GGP Max_Current, 2
    AAP 6,0
    AAP 6,1
    AAP 6,2

    GGP Sandby_Current, 2
    AAP 7,0
    AAP 7,1
    AAP 7,2

    WAIT TICKS,0,10

    SAP 209,0,0
    SAP 209,1,0
    SAP 209,2,0

    GAP 209,0
    AAP 1,0

    GAP 209,1
    AAP 1,1

    GAP 209,2
    AAP 1,2

    GAP 209,0
    AAP 0,0

    GAP 209,1
    AAP 0,1

    GAP 209,2
    AAP 0,2

    WAIT TICKS,0,10

    SGP 10, 2, 0   
    JA MainLoop


// ========================================================================
// 2. START INIT
// ========================================================================

StartInit:

    GGP CLgamma_Vmin, 2
    AAP 108,0,300000
    AAP 108,1,300000
    AAP 108,2,300000

    GGP CLgamma_Vmax, 2
    AAP 109,0,600000
    AAP 109,1,600000
    AAP 109,2,600000

    GGP CL_Maxgamma, 2
    AAP 110,0,255
    AAP 110,1,255
    AAP 110,2,255

    GGP CL_Beta, 2
    AAP 111,0,255
    AAP 111,1,255
    AAP 111,2,255

    GGP CL_Currentmin, 2
    AAP 113,0,50
    AAP 113,1,50
    AAP 113,2,50

    GGP CL_Currentmax, 2
    AAP 114,0,240
    AAP 114,1,240
    AAP 114,2,240

    GGP CL_Startup, 2
    AAP 126,0,25
    AAP 126,1,25
    AAP 126,2,25

    GGP CLmax_Correction_Tolerance, 2
    AAP 125,0,100
    AAP 125,1,100
    AAP 125,2,100

    GGP Pos_Window, 2
    AAP 134,0,100
    AAP 134,1,100
    AAP 134,2,100

    GGP CL_Upscale_Delay, 2
    AAP 120,0,1000
    AAP 120,1,1000
    AAP 120,2,1000

    GGP CL_Downscale_Delay, 2
    AAP 121,0,10000
    AAP 121,1,10000
    AAP 121,2,10000

    GGP CL_Correction_VelocityP, 2
    AAP 115,0,3000
    AAP 115,1,3000
    AAP 115,2,3000

    GGP CL_Correction_VelocityI, 2
    AAP 116,0,20
    AAP 116,1,20
    AAP 116,2,20

    GGP CL_Correction_VelocityI_Clipping, 2
    AAP 117,0,10
    AAP 117,1,10
    AAP 117,2,10

    GGP CL_Correction_VelocityDV_Clock, 2
    AAP 118,0,0
    AAP 118,1,0
    AAP 118,2,0

    GGP CL_Correction_VelocityDV_Clipping, 2
    AAP 119,0,100000
    AAP 119,1,100000
    AAP 119,2,100000

    GGP CL_Correction_Pos, 2
    AAP 124,0,65536
    AAP 124,1,65536
    AAP 124,2,65536

    GGP Max_Encoder_Deviation, 2     //Needed for Homing and for movement: When the actual position (parameter 1) and the encoder position (parameter 209) differ more than set here the motor will be stopped. This function is switched off when the maximum deviation is set to zero.
    AAP 212,0,1000
    AAP 212,1,1000
    AAP 212,2,1000

    GPP Max_velocity_Deviation, 2
    AAP 213,0,30000
    AAP 213,1,30000
    AAP 213,2,30000

    WAIT TICKS,0,10

    SGP 10, 2, 0
    JA MainLoop

// ========================================================================
// 3. DISABLE CLOSED LOOP
// ========================================================================
        
DisableClosedLoop:

    SAP 129,0,0
    SAP 129,1,0
    SAP 129,2,0

    WaitDisableClosedLoop:

        WAIT TICKS,0,1
        GAP 133,0
        COMP 0
        JC NE, WaitDisableClosedLoop

        WAIT TICKS,0,1
        GAP 133,1
        COMP 0
        JC NE, WaitDisableClosedLoop

        WAIT TICKS,0,1
        GAP 133,2
        COMP 0
        JC NE, WaitDisableClosedLoop

    WAIT TICKS,0,10
        
    SGP 10, 2, 0
    JA MainLoop

DisableClosedLoop_Routine:

    SAP 129,0,0
    SAP 129,1,0
    SAP 129,2,0

    WaitDisableClosedLoop_Routine:

    WAIT TICKS,0,1
    GAP 133,0
    COMP 0
    JC NE, WaitDisableClosedLoop_Routine

    WAIT TICKS,0,1
    GAP 133,1
    COMP 0
    JC NE, WaitDisableClosedLoop_Routine

    WAIT TICKS,0,1
    GAP 133,2
    COMP 0
    JC NE, WaitDisableClosedLoop_Routine

    RSUB

// ========================================================================
// 4. ENABLE CLOSED LOOP
// ========================================================================
        
EnableClosedLoop:

    SAP 129,0,1
    SAP 129,1,1
    SAP 129,2,1

    WaitEnableClosedLoop:

        WAIT TICKS,0,1
        GAP 133,0
        COMP 1
        JC NE, WaitEnableClosedLoop

        WAIT TICKS,0,1
        GAP 133,1
        COMP 1
        JC NE, WaitEnableClosedLoop

        WAIT TICKS,0,1
        GAP 133,2
        COMP 1
        JC NE, WaitEnableClosedLoop

        WAIT TICKS,0,10

        SAP 209,0,0
        GAP 209,0
        AAP 1,0
        GAP 209,0
        AAP 0,0

        SAP 209,1,0
        GAP 209,1
        AAP 1,1
        GAP 209,1
        AAP 0,1

        SAP 209,2,0
        GAP 209,2
        AAP 1,2
        GAP 209,2
        AAP 0,2

    WAIT TICKS,0,10

    SGP 10, 2, 0
    JA MainLoop

// ========================================================================
// 5. START HOME
// ========================================================================

// 2 options below

// ========================================================================
// 6. START MOVE
// ========================================================================

StartMove:

    SGP 10, 2, 0            // Reset State to 0 (Idle/Done) clear command immediately

    GGP Max_Speed, 2
    AAP 4,0
    AAP 4,1
    AAP 4,2

    GGP Target_Pos, 2
    AAP 0,0
    AAP 0,1
    AAP 0,2
    
    MVP ABS,0,0
    MVP ABS,1,0
    MVP ABS,2,0

    JA MonitorLoop

    // =====================================================
    // MONITOR LOOP
    // =====================================================
    MonitorLoop:

    //AXIS 0
    GAP 8,0
    COMP 1
    JC EQ,Axis1

    GAP 3,0
    COMP 0
    JC EQ,EmergencyStop

    //AXIS 1
    Axis1:

    GAP 8,1
    COMP 1
    JC EQ,Axis2

    GAP 3,1
    COMP 0
    JC EQ,EmergencyStop

    //AXIS 2
    Axis2:

    GAP 8,2
    COMP 1
    JC EQ,ContinueLoop

    GAP 3,2
    COMP 0
    JC EQ,EmergencyStop

    ContinueLoop:

      WAIT TICKS,0,1
      JA MonitorLoop


   // =====================================================
   // STOP EVERYTHING
   // =====================================================
   EmergencyStop:

      SAP 17,0, 100000
      SAP 17,1, 100000
      SAP 17,2, 100000

      MST 0
      MST 1
      MST 2

   WAIT TICKS,0,10
   SGP 10, 2, 0
   JA MainLoop

// ========================================================================
// 7. POWER OFF
// ========================================================================

PowerOff:
    
    MST 0                   // Motor STop Axis 0
    MST 1                   // Motor STop Axis 1
    MST 2                   // Motor STop Axis 2
    WAIT TICKS,0,10
    CSUB DisableClosedLoop_Routine
    SAP 6, 0, 0
    SAP 6, 1, 0
    SAP 6, 2, 0
    SAP 7, 0, 0
    SAP 7, 1, 0
    SAP 7, 2, 0

   WAIT TICKS,0,10
   SGP 10, 2, 0
   JA MainLoop
        
// ========================================================================
// 999. END LOOP OF TMCM PROGRAM - SOP FIRMWARE
// ========================================================================

EndLoop:

    MST 0
    MST 1
    MST 2
    STOP                     // Stops execution of the TMCL program















// ========================================================================
// SYNCHRONOUS HOMING (Master Axis 0 Strategy) a “reference search” (homing)
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

    SAP 209,0,0
    SAP 209,1,0
    SAP 209,2,0

    GAP 209,0
    AAP 1,0

    GAP 209,1
    AAP 1,1

    GAP 209,2
    AAP 1,2

    GAP 209,0
    AAP 0,0

    GAP 209,1
    AAP 0,1

    GAP 209,2
    AAP 0,2


    SGP 10, 2, 0            // Reset State to 0 (Idle/Done)
    JA MainLoop
















// ========================================================================
// SYNCHRONIZED HOMING ROUTINE
// Axis 0 = Master Homing Axis
// One home switch at bottom
// All axes move together vertically
// ========================================================================

StartHome:

    // ------------------------------------------------------------
    // Temporarily relax encoder deviation during homing
    // (prevents nuisance following errors)
    // ------------------------------------------------------------

    SAP 212,0,5000
    SAP 212,1,5000
    SAP 212,2,5000

    // ------------------------------------------------------------
    // Configure Reference Search for AXIS 0 (SWITCH IN 0)
    // ------------------------------------------------------------

    // Mode 1 (left) 65 (right):
    // Search home switch in POSITIVE DIRECTION (TO THE RIGHT = DOWNWARDS)

    SAP 193,0,65

    // Fast search speed
    SAP 194,0,2000

    // Slow precision latch speed
    SAP 195,0,200

    // Apply same velocity to other 2 axes
    SAP 4,1,2000
    SAP 4,2,2000

    ROR 1
    ROR 2

    RFS START,0

WaitHome:

    RFS STATUS,0
    COMP 0
    JC EQ,HomeFinished

    // Optional:
    // If one of the other axis stalls unexpectedly,

    GAP 3,1
    COMP 0
    JC EQ,MonitorLoopHoming

    GAP 3,2
    COMP 0
    JC EQ,MonitorLoopHoming

    WAIT TICKS,0,1
    JA WaitHome

HomeFinished:

    // Stop slave axes
    MST 1
    MST 2

    WAIT TICKS,0,10

    // Zero all step positions
    SAP 209,0,0
    SAP 209,1,0
    SAP 209,2,0

    GAP 209,0
    AAP 1,0

    GAP 209,1
    AAP 1,1

    GAP 209,2
    AAP 1,2

    GAP 209,0
    AAP 0,0

    GAP 209,1
    AAP 0,1

    GAP 209,2
    AAP 0,2

    WAIT TICKS,0,10

    // Restore normal encoder deviation protection

    SAP 212,0,1000
    SAP 212,1,1000
    SAP 212,2,1000

    // Homing complete
    SGP 10,2,0

    JA MainLoop

MonitorLoopHoming:
            
    SAP 17,0, 100000
    SAP 17,1, 100000
    SAP 17,2, 100000

    MST 0
    MST 1
    MST 2

    WAIT TICKS,0,10
    SGP 10,2,99

    JA MainLoop

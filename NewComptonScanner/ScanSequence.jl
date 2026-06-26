# Complete startup + calibration + measurement scan sequence for the
# TMCM-3351 controlled by TMCMCode_newversion.tmc.

cd("/home/gelab/testJulia/ComptonScanner/NewComptonScanner")
using Pkg
Pkg.activate(".")
using TrinamicMotionControl
import TrinamicMotionControl: query, set_axis_parameter, get_axis_parameter
include("tmcl_control_layer.jl")
using .TMCLControlLayer

const BOARD_IP    = "gelab-serial01"
const BOARD_PORT  = 2001
const GP_BANK     = 2

dev = connect_board(BOARD_IP, BOARD_PORT)
sleep(2.0)                     # allow board to reach MainLoop before sending commands
#### 1st block to run ####
#Run this block ####################
#power_on(dev);            wait_for_idle(dev)   # set motion params, sync encoder/actual/target
#start_init(dev);          wait_for_idle(dev)   # load closed-loop PID parameters
#disable_closed_loop(dev); wait_for_idle(dev)
#enable_closed_loop(dev);  wait_for_idle(dev)   # clean CL init before any move
#reference_zero(dev);      wait_for_idle(dev)   # set current sled positions as encoder origin
#Or just startup ###################
startup!(dev)                 # PowerOn → StartInit → DisableCL → EnableCL
                              # (ReferenceZero is NOT called here — see calibrate!)

#ONCE AFTER UNPLUGGING THE BOARD BEFORE PERFORMING THE CALIBRATION< OTHERWISE IT"S REMEMBERED!!!!!
#RefZero_run_only_once_after_unplugging_board!(dev)  # ReferenceZero → wait_for_idle

#### 2nd block to run: Calibrate the 3 axis at the same time ####
# After power cycle: always run calibrate! — it re-zeros encoder then descends to blocks.
# After Julia restart (no power cycle): skip calibrate! if read_axis_status shows valid
# calib positions — the encoder reference survived and EEPROM values are still correct.
calibrate!(dev)               # SimultaneousCalibration → save to EEPROM

#### 3rd block to run ####
const MOVE_NSTEPS = 500_000   # microsteps above calibration block
const DEFAULT_MAX_SPEED = 51_200
#Run this without entering measuring mode and to move the 3 axis####################
move_all_axes_to(dev, MOVE_NSTEPS, DEFAULT_MAX_SPEED); wait_for_idle(dev)
#Run this to move the 3 axis then enter measurement mode (de-energize motors)
#move_all_axes_to(dev, MOVE_NSTEPS, DEFAULT_MAX_SPEED); wait_for_idle(dev)
#enter_measurement_mode(dev)   # includes 2 s settle + wait_for_idle internally
#... acquire data ...
#end_measurement!(dev)
#Run this to move one axis at a time independently (ax: 0/1/2, position: absolute encoder usteps)
#const MOVE_TO_POSITION = 100_000
#move_absolute_axis_to(dev, 0, MOVE_TO_POSITION, DEFAULT_MAX_SPEED); wait_for_idle(dev)  # axis 0
#move_absolute_axis_to(dev, 1, MOVE_TO_POSITION, DEFAULT_MAX_SPEED); wait_for_idle(dev)  # axis 1
#move_absolute_axis_to(dev, 2, MOVE_TO_POSITION, DEFAULT_MAX_SPEED); wait_for_idle(dev)  # axis 2

#Run this to move one axis at a time to a position above its calibration block (nsteps above block)
#move_axis_above_calib(dev, 0, MOVE_NSTEPS, DEFAULT_MAX_SPEED); wait_for_idle(dev)  # axis 0
#move_axis_above_calib(dev, 1, MOVE_NSTEPS, DEFAULT_MAX_SPEED); wait_for_idle(dev)  # axis 1
#move_axis_above_calib(dev, 2, MOVE_NSTEPS, DEFAULT_MAX_SPEED); wait_for_idle(dev)  # axis 2

const MOVE_CM    = 2.0   # cm above calibration block
const SPEED_CM_S = 0.5   # cm/s  (= 5 mm/s = 51,200 usteps/s)
#Run this to move all 3 axes 2 cm above calibration blocks
move_all_axes_to_cm(dev, MOVE_CM, SPEED_CM_S); wait_for_idle(dev)

#Run this to move all 3 axes 2 cm above calibration then enter measurement mode (de-energize motors)
#move_all_axes_to_cm(dev, MOVE_CM, SPEED_CM_S); wait_for_idle(dev)
#enter_measurement_mode(dev)   # includes 2 s settle + wait_for_idle internally
#... acquire data ...
#end_measurement!(dev)

#Run this to move one axis at a time 2 cm above its calibration block
#move_axis_above_calib_cm(dev, 0, MOVE_CM, SPEED_CM_S); wait_for_idle(dev)  # axis 0
#move_axis_above_calib_cm(dev, 1, MOVE_CM, SPEED_CM_S); wait_for_idle(dev)  # axis 1
#move_axis_above_calib_cm(dev, 2, MOVE_CM, SPEED_CM_S); wait_for_idle(dev)  # axis 2


#### 4th block : Power off and potentially stop code looping on tmcm board ####
#shutdown!(dev)
#This stops the TMCM program looping on the board
#end_program(dev)




# Direct examples
#Set speed via SGP and read speed via GGP : Global parameters set constant values
#query(dev, 9, GP_MAX_SPEED, GP_BANK, 51_200)
#query(dev, 10, GP_MAX_SPEED, GP_BANK, 0)

#Set speed via SAP and read speed via GAP : This changes motor axis values
#set_axis_parameter(dev, GP_MAX_SPEED, 0, 51_200) # Set speed for axis 0
#get_axis_parameter(dev, GP_MAX_SPEED, 0)         # Read speed for axis 0
#get_axis_parameter(dev,6, 0)         #reads the max voltage

#read the current voltage
#query(dev, 15, 8, 1, 0)   # GIO command = 15, port 8, bank 1

#Read status of the board
#board_status(dev)         # log supply voltage [V] and temperature [°C / K]
#read_axis_status(dev)     # get axis status : calibration point and encoder positions for the 3 axis
#read_closed_loop_status(dev)
#is_program_running(dev)   # Ping (cmd 100): returns true if TMCMCode_newversion is looping
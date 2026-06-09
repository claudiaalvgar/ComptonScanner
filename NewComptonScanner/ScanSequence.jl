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
startup!(dev)                 # PowerOn → StartInit → DisableCL → EnableCL → ReferenceZero

#### 2nd block to run ####
calibrate!(dev)               # SimultaneousCalibration

#### 3rd block to run ####
const MOVE_NSTEPS = 500_000   # microsteps above calibration block
const DEFAULT_MAX_SPEED = 51_200
#Run this without entering measuring mode ####################
move_all_axes_to(dev, MOVE_NSTEPS, DEFAULT_MAX_SPEED); wait_for_idle(dev)
#Run this entering measuring mode ####################
#move_and_measure!(dev, MOVE_NSTEPS, DEFAULT_SPEED) #Calls move_all_axes_to and enter_measurement_mode
#exit_measurement_mode!(dev)

#### 4th block : Power off and potentially stop code looping on tmcm board ####
#shutdown!(dev)
#This stops the TMCM program looping on the board
#end_program(dev) = set_global_parameter(dev, GP_TMCM_COMMAND, 999)
#end_program(dev)



# Direct examples
#Set speed via SGP and read speed via GGP : Global parameters set constant values
#query(dev, 9, GP_MAX_SPEED, GP_BANK, 51_200)
#query(dev, 10, GP_MAX_SPEED, GP_BANK, 0)

#Set speed via SAP and read speed via GAP : This changes motor axis values
#set_axis_parameter(dev, GP_MAX_SPEED, 0, 51_200) # Set speed for axis 0
#get_axis_parameter(dev, GP_MAX_SPEED, 0)         # Read speed for axis 0

#read the current voltage
#query(dev, 15, 8, 1, 0)   # GIO command = 15, port 8, bank 1
#board_status(dev)              # log supply voltage [V] and temperature [°C / K]
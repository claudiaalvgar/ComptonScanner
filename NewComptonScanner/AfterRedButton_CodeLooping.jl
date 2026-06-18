#ASSUME THE BOARD WAS ALREADY CALIBRATED AND THE ENCODER ZERO POSITION WAS SET IN THE PREVIOUS SESSION AND THAT THE USB WAS PLUGGED IN SO THE BOARD WAS NOT FULLY POWERED OFF
#SO VALUES LIKE ENCODER POSITIONS ETC. ARE SAVED

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
sleep(2.0) 

#Check the values stay for calibration point and encoder positions for the 3 axis and that closed loop is disabled
read_axis_status(dev)
read_closed_loop_status(dev)


startup!(dev)                # Re enables closed loop that is disabled after unpressing the red botton

#Check the values stay for calibration point and encoder positions should have moved a bit because of enabling closed loop
#for the 3 axis and that closed loop is enabled
read_axis_status(dev)
read_closed_loop_status(dev)

# We can calibrate again if needed, recommended since diabling and enabling the closed loop moves a bit the sleds and the encoder positions
calibrate!(dev) 

#or just start moving the 3 axis simultaneously
const MOVE_CM    = 5.0   # cm above calibration block
const SPEED_CM_S = 0.5   # cm/s (= 5 mm/s = 51,200 usteps/s)
#Run this without entering measuring mode and to move the 3 axis
move_all_axes_to_cm(dev, MOVE_CM, SPEED_CM_S); wait_for_idle(dev)
#or move one axis at a time
#move_axis_above_calib_cm(dev, 0, MOVE_CM, SPEED_CM_S); wait_for_idle(dev)  # axis 0
#move_axis_above_calib_cm(dev, 1, MOVE_CM, SPEED_CM_S); wait_for_idle(dev)  # axis 1
#move_axis_above_calib_cm(dev, 2, MOVE_CM, SPEED_CM_S); wait_for_idle(dev)  # axis 2




#Equivalent in microsteps (1 cm = 102,400 usteps; 0.5 cm/s = 51,200 usteps/s):
#const MOVE_NSTEPS = 500_000     # microsteps above calibration block (≈ 5 cm)
#const DEFAULT_MAX_SPEED = 51_200  # usteps/s
#move_all_axes_to(dev, MOVE_NSTEPS, DEFAULT_MAX_SPEED); wait_for_idle(dev)
#or move one axis at a time (usteps)
#move_axis_above_calib(dev, 0, MOVE_NSTEPS, DEFAULT_MAX_SPEED); wait_for_idle(dev)  # axis 0
#move_axis_above_calib(dev, 1, MOVE_NSTEPS, DEFAULT_MAX_SPEED); wait_for_idle(dev)  # axis 1
#move_axis_above_calib(dev, 2, MOVE_NSTEPS, DEFAULT_MAX_SPEED); wait_for_idle(dev)  # axis 2

#or move one axis at a time but absolute position
#const MOVE_TO_POSITION = 100_000 #absolute position with respect to the 0 position (it would go down with respect to the zero position)
#move_absolute_axis_to(dev, 0, MOVE_TO_POSITION, DEFAULT_MAX_SPEED); wait_for_idle(dev)  # axis 0
#move_absolute_axis_to(dev, 1, MOVE_TO_POSITION, DEFAULT_MAX_SPEED); wait_for_idle(dev)  # axis 1
#move_absolute_axis_to(dev, 2, MOVE_TO_POSITION, DEFAULT_MAX_SPEED); wait_for_idle(dev)  # axis 2



#BEFORE PRESSING THE RED BUTTON TO POWER OFF THE BOARD, FOR A CORRECT TERMINATION OF THE SYSTEM RUN:
#For a correct termination of the system before pressing the red button run: 
shutdown!(dev)
#and maybe if we want our tmcm code to stop looping in the board 
end_program(dev)
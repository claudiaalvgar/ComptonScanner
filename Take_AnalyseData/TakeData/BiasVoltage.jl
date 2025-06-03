# CHECK THAT THE DETECTOR IS COOLED DOWN IN @info MESSAGES RUNNING:
#include("/home/gelab/Software/K2/k2_OnlineMonitor/K2OM.jl")


#For Compton Scanner + 3200V

#=
#using GeDetK2Control (not sure if we need this)
using VoltageControl

m = NHQ_226("HV", "gelab-serial06", 2061) #TCP Port(Data) in Port 7 in the serial

# :A channel 1 in HV :B is channel 2 in HV
# Check if this returns same as the reading in  HV device

VoltageControl.get_measured_voltage(m, :A)

# set voltage to 0

VoltageControl.voltage_goto(m, :A, 0)

set_ramp_speed(m, :A, 5)

# Set the voltage to 30V at a ramp speed of 5 V/s

VoltageControl.voltage_goto(m, :A, 10)
#sleep(5)
#VoltageControl.voltage_goto(m, :A, 30)

#...etc...to + 3200V
=#


#For the other setup BeGe - 3200V

#=
using GeDetK2Control

myhv = k2.k2HV()

k2.set_ramp_speed(myhv, :B, 2)

k2.voltage_goto(myhv, :B, 10)

=#
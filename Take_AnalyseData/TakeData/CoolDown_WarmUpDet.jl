########################################
COOL DOWN AND WARM UP
MULTIMETER 01 Black (segment 4) - Red (segment 1)
MULTIMETER 02 Yellow (segment 2) - Blue (segment 3)
########################################

# Check the current temperature
#include("/home/gelab/Software/K2/k2_OnlineMonitor/K2OM.jl")

# First we run the multimeter script
#include("/home/gelab/Multimeter_Script/multimeter_script.jl")


using GeDetK2Control

# In Centigrades
# Cool Down
#GeDetK2controller_coldtip_temperature(-190)
# Warm Up
#GeDetK2controller_coldtip_temperature(50)
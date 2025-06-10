#!/bin/bash

# Pass number to Julia script
# n=0 for Ba data (1 file), n=1 n=2 (file 1, file 2, ..., file 8) for Cs data
n=1 


julia --project=. Pulse_Spectrum_TrapFilter_allkeys.jl $n

#sleep 4

#n=8

#julia --project=. Pulse_Spectrum_TrapFilter_allkeys.jl $n

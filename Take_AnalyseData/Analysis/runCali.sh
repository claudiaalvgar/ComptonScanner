#!/bin/bash

# Pass number to Julia script
n=7

julia --project=. Pulse_Spectrum_TrapFilter_allkeys.jl $n

sleep 4

n=8

julia --project=. Pulse_Spectrum_TrapFilter_allkeys.jl $n

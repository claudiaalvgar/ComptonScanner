using LegendHDF5IO
using Statistics
using ProgressMeter
using Plots
using StatsBase
using LsqFit
using Revise
using RadiationDetectorDSP
using LegendDSP

include("Max_TrapFilter.jl")
using .Max_TrapFilter



#file = "/remote/ceph/user/a/alvarez/ComptonScanner/Ba_Data/raw_data/133Ba_Compton_R_0.0mm_Z_-0.0mm_Phi_138.7deg_T_80.0K_measuretime_300sec-ICPC-20250522T144857Z.lh5"

file = "/remote/ceph/user/a/alvarez/ComptonScanner/Cs_Data/raw_data/R_51.0mm_Z_0.0mm_Phi_113.1deg_T_80.0K_measuretime_300sec-ICPC-20250523T132022Z.lh5"

t = lh5open(file) do h
    h["1"][:]
end

#Ba
#truebaseline_previousdata = 8546.0
#tau = 59000

#Cs
truebaseline_previousdata = 8542.0
tau = 56000
dt = 4 #ns
tau_alg = tau / dt

av = 80
gap = 300

#plot 10 raw waveform and pass mean value from previous studies

plot(0:dt:1200*dt-dt, t.samples[findall(t.channel .== 1)][1:10], xlabel = "Time in ns", ylabel = "Signal in ADC units", fmt = :png, size = (600,400), legend = false, title = "Raw waveforms")
hline!([truebaseline_previousdata])


# Corrected signal waveform

tc = @showprogress map(p -> let pc = InvCRFilter(tau_alg)(p .- truebaseline_previousdata)
    pc .- mean(pc[1:200]) # mean(pc[1000:1200]) - mean(pc[1:200])
    end, t.samples[findall(t.channel .== 1)]);


plot(0:4:1200*4-4, tc[1:10], xlabel = "Time in ns", ylabel = "Signal in ADC units", fmt = :png, size = (600,400), legend = false, title = "Baseline- and decay-corrected waveforms")

#savefig("CorrectedSignal_Cs_file1.png")


#=
# Plot each filtered waveform with proper time axis (assuming 4 ns per sample)

filtered = TrapezoidalChargeFilter(av, gap).(tc[1:10])

for f in filtered
    time = 0:4:(length(f)-1)*4  # 4 ns per sample
    plot!(time, f, label = "")
end

display(current())
=#


#PRINT CORRECTED PEAKS + TRAPEZOID

threshold = 20

#=
offset_ns = 2000
peakno = 1

f_ = TrapezoidalChargeFilter(av, gap)(tc[peakno])
time = (0:4:(length(f_)-1)*4) .+ offset_ns  # 4 ns per sample
plot(time, f_, xlabel = "Time in ns", ylabel = "Signal [ADC Counts]", label="Filtered")
plot!(0:4:(length(tc[peakno])-1)*4, tc[peakno], label="Original")

L_time = av*dt + offset_ns
gap_time = (gap*dt) + L_time
vline!([L_time], label = "Average = $av ($(av*dt) ns)")
vline!([gap_time], label = "Gap = $gap ($(gap*dt) ns)")

#savefig("Trapfilter_Cs_$(peakno)_av_$(av)_gap_$(gap).png")

ADC_Counts =  maximum(f_)
println("ADC counts returned by filter: $(ADC_Counts)")


Max_trapezoids = Max_TrapFilter.@call_max_height(f_, threshold)

println("ADC counts returned by filter: $(Max_trapezoids)")


#annotate!(500, 300, text("Energy = $(maximum(1.09 * TrapezoidalChargeFilter(av,gap)(tc[peakno]))) keV", :blue, 10))
=#

#PLOT TRAPEZOIDS RETURNED BY FILTER

#plot(TrapezoidalChargeFilter(av,gap).(tc)[1:10], xlabel = "Time in ns", ylabel = "Signal after Trapezoid Filter")



#ENERGY SPECTRUM
#=
filtered_Trapezoids = TrapezoidalChargeFilter(av, gap).(tc)

# This returns a vector of vectors (one peak can have 2 max if overlapped)

Max_wfrm = Max_TrapFilter.@call_max_height(filtered_Trapezoids, threshold)
filtered_results = filter(x -> x !== nothing, Max_wfrm)
println("My trapezoids max: $(Max_wfrm[1:11])")

flat_max_adcs = collect(Iterators.flatten(filtered_results))

max_adc_notresolving = maximum.(filtered_Trapezoids)
println("Trapezoids just one max: $(max_adc_notresolving[1:11])")

#applying a threshold for the max, we can get 2 max per signal if overlapped pulses
#stephist(1.09 .* flat_max_adcs, bins = 0:1000, fmt = :png, label = "",xlabel = "Energy [keV]", ylabel = "Counts", xlimits=(0,500), ylimits = (0,10000))

#plot with just maximum of the trapezoids (one per signal)
stephist(1.09 .* max_adc_notresolving, bins = 0:1000, fmt = :png, label = "",xlabel = "Energy [keV]", ylabel = "Counts", xlimits=(0,500), ylimits = (0,10000))


vline!([31,81,276,302,356,383], label = "133Ba lines")
vline!([31,81,276,302,356,383] .+ 31, label = "133Ba lines + 31 keV")
vline!([31,81,276,302,356,383] .+ 81, label = "133Ba lines + 81 keV")

#savefig("BaSpectrum_av_$(av)_gap_$(gap)_maxvalue_range0-500.png")
#savefig("BaSpectrum_av_$(av)_gap_$(gap)_threshold_$(threshold)_range0-500.png")
=#

using TypedTables
using LegendHDF5IO

function sortevents(data_in::Table; ch = 1:5, sync = [9,10])
    evt_t = data_in.timestamp[:]
    chid = data_in.channel[:]
    dataidx = findall(c -> c in ch, chid)
    sort!(dataidx, lt = (a,b) -> evt_t[a] < evt_t[b] || (evt_t[a] == evt_t[b] && chid[a] < chid[b]))
    i = 1
    N = length(dataidx)
    while i < N - length(ch)
        if all(chid[dataidx[i:i+length(ch)-1]] .== ch) && all(evt_t[dataidx[i]] .== evt_t[dataidx[i:i+length(ch)-1]])
            i += length(ch)
        else
            #@info evt_t[dataidx[i:i+length(ch)-1]]
            di = findfirst(evt_t[dataidx[i:i+length(ch)-1]] .> evt_t[dataidx[i]])
            #@warn "idx : $(di), i: $i, deleting $(length(i:i+di-2)) entries"
            deleteat!(dataidx, i:i+di-2)
            N = length(dataidx)
        end
    end
    t = data_in[dataidx[1:i-1]]
    t.daqevtno .= div.(eachindex(t).-1, length(ch)).+1 # reset event numbers
    
    # Check that the Table fulfills the wanted requirements
    @assert all(t.channel .== (eachindex(t) .- 1) .% length(ch) .+ 1)
    @assert all([all(t.timestamp[i:i+length(ch)-1] .== t.timestamp[i]) for i in 1:length(ch):length(t)])
    @assert all([all(t.daqevtno[i:i+length(ch)-1] .== t.daqevtno[i]) for i in 1:length(ch):length(t)])
    
    t
end

#read in part of the dataset, skip the samples for increasing the sorting performance
function read_raw_file(filename::AbstractString, ch = 1:5)
    data_in = LHDataStore(filename, "r") do h5f
        vcat([h5f[g][:] for g in sort( keys(h5f), by = x -> parse(Int, x))]...)
    end
    sortevents(data_in, ch = ch)
end

function update_directory(directory::AbstractString, ch = 1:5)
    files = filter(x -> endswith(x, "h5"), joinpath.(directory, readdir(directory)))
    for f in files
        h = LHDataStore(f)
        if !haskey(h, "1") 
            close(h)
            continue
        end
    	@info "Updating $(basename(f))"
    	updated_table = read_raw_file(f, ch)
    	LHDataStore(f * "_new", "cw") do h
    	    h["segBEGe"] = updated_table
    	end
    	mv(f, f*"_old")
    	mv(f*"_new", f)
    end
    nothing
end

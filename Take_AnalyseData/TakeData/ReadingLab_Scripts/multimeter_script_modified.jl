using Sockets, Dates

# Configuration
#
# Temperature measurement

abstract type Device end

struct Lakeshore <: Device
    name::String
    ip::String
    port::Int

    """
        NHQ_206L(name::String, ip::String, port::Int)

        Create NHQ_206L for use with control functions.

            # Arguements
            - `name::String`: Internal reference name for module.
            - `ip::String`: Net address for module.
            - `port::Int`: Port address on given net address.
    """

    function Lakeshore(name::String = "Lakeshore", ip::String = "gelab-serial09", port::Int = 2051)
        device = new(name, ip, port)
        return device
    end

    function Base.show(io::IO, device::Lakeshore)
      for n in fieldnames(typeof(device))
        println(io, "$n: $(getfield(device,n))")
      end
    end
end

function query(device::Lakeshore, cmd::String; timeout=1.0)::String
    c = connect(device.ip,device.port)
    write(c,cmd)
    write(c,"\n")
    # write(c,"KRDG? 0\n")
    response = ""
    task = @async response = readline(c)
    t0 = time()
    t=0.0
    while t < timeout
        if task.state == :done break end
        t = time()-t0
        sleep(0.01)
    end
    close(c)
    if t >= timeout
        error("Timeout! Device did not answer.")
    else
        return response
    end
end

 function get_temperatures(ls::Lakeshore)
    temperatures = query(ls,"KRDG? 0")
    # return map(x -> parse(Float64, x[2:end]), split(temperatures, ","))
    return map(x -> x[2:end], split(temperatures, ","))
 end
 lake_name = Lakeshore()



#Resistance measurement
host1 = "gelab-multimeter01"    # Replace with your hostname or IP
host2 = "gelab-multimeter02"    # Replace with your hostname or IP
port =    5555       # Replace with the actual port


# N = 5 # number of measurements
t = 60.0                         # Time interval in seconds
outfile = "resistance_log_$(Dates.format(Dates.now(UTC), "YYYYmmddTHHMMSSZ")).csv"  # Output file path

# Helper functions

# sends the SCPI command followed by a new line to the instrument
function send_cmd(sock, cmd::String)
    write(sock, cmd * "\n")
    return
end
# sends the SCPI command followed by a new line to the instrument
function query(sock, cmd::String)
       send_cmd(sock, cmd)
	#This reads from the socket sock until it sees a newline character ('\n'), which is how most SCPI devices (like multimeters) terminate their responses.
	return String(readuntil(sock, '\n')) 
end

# Connect to the multimeter

sock1 = connect(host1, port)
sock2 = connect(host2, port)

# Setup multimeter

send_cmd(sock1, "*RST")
send_cmd(sock1, ":FUNCtion:RESistance")
@info query(sock1, ":FUNCtion?")
#send_cmd(sock1, ":MEASure:RESistance MAX")
@info query(sock1, ":MEASure:RESistance:RANGe?")

send_cmd(sock2, "*RST")
send_cmd(sock2, ":FUNCtion:RESistance")
@info query(sock2, ":FUNCtion?")
#send_cmd(sock2, ":MEASure:RESistance MAX")
@info query(sock2, ":MEASure:RESistance:RANGe?")




# Open log file

io = open(outfile,"w")

try
    write(io, "t1,resistance_seg4,range_seg4,t2,resistance_reference,range_reference,t3,pt100-1,pt100-2,t4\n")
    #for i in 1:N
    while true
	timestamp1 = Dates.format(now(UTC), "YYYYmmddTHHMMSSZ")
	resistance_mult1  = query(sock1, ":MEASure:RESistance?")
	resistance_range1 = query(sock1, ":MEASure:RESistance:RANGe?")
	timestamp2 = Dates.format(now(UTC), "YYYYmmddTHHMMSSZ")
	resistance_mult2  = query(sock2, ":MEASure:RESistance?")
	resistance_range2 = query(sock2, ":MEASure:RESistance:RANGe?")
	timestamp3 = Dates.format(now(UTC), "YYYYmmddTHHMMSSZ")
	temperatures = get_temperatures(lake_name)
	timestamp4 = Dates.format(now(UTC), "YYYYmmddTHHMMSSZ")
	println(io, "$timestamp1,$resistance_mult1,$resistance_range1,$timestamp2,$resistance_mult2,$resistance_range2,$timestamp3, $(temperatures[1]), $(temperatures[2]),$timestamp4")
	flush(io)
	println("[$timestamp1] Resistance: $resistance_mult1 Ω, (range: $resistance_range1) $resistance_mult2 Ω (range: $resistance_range2),  Temperatures: $(temperatures[1]), $(temperatures[2])")
        sleep(t)
    end
catch e
    if isa(e, InterruptException)
        println("Interrupted by user. Stopping gracefully...")
    else
        println("Unexpected error: ", e)
    end
finally
    println("Closing file...")
    flush(io)
    close(io)
end

# Close socket

close(sock1)
close(sock2)

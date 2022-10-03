
"""
CordraPayload(filename::String, mime::String)

Use the `payload(...)` method to construct a CordraPayload for a local file.

Payloads represent the large free-form content of a Cordra digital object. They
are often images, data files or other hard-to-index data items.

Example:
```julia-repl
julia> cp1=payload(joinpath("Desktop","trialC.svg"), "image/svg+xml")
julia> cp2=cp"Desktop\\GSR2020.tsv"
julia> create_object(cc, json, "Stuff", payloads = [cp1, cp2])
```
"""
struct CordraPayload
    name::String
    filename::String
    mime::String
    function CordraPayload(name::String, filename::String, mime::String)
        @assert isfile(filename) "CordraPayload: $filename is not an existing file."
        new(name, filename, mime)
    end
end

Base.show(io::IO, cp::CordraPayload) = print(io, "CordraPayload($(cp.name), $(cp.mime))")

"""
    payload(fname::AbstractString, mime=nothing)
    payload(name::AbstractString, fname::AbstractString, mime=nothing)

Creates a CordraPayload from a filename.  If `mime` is nothing then
guesses the mime-type using HTTP.sniff(...).
"""
function payload(name::AbstractString, fname::AbstractString, mime=nothing)
    @assert isfile(fname) "payload(...): $fname is not an existing file."
    mime = something(mime, open(fname, "r") do io
        HTTP.sniff(read(io, 512))
    end)
    CordraPayload(name, fname, mime)
end
function payload(fname::AbstractString, mime=nothing)
    payload(splitpath(fname)[end], fname, mime)
end


"""
A macro to create a simple payload from a filename.  The macro sniffs
the file to determine the MIME-type (with more or less success).
"""
macro cp_str(fname::AbstractString)
    payload(fname)
end

function _tomultipart(cpls::Vector{CordraPayload})
    res = Dict{String,HTTP.Multipart}()
    ios = IO[]
    for cpl in cpls
        io = open(cpl.filename, "r")
        push!(ios, io)
        res[cpl.name] = HTTP.Multipart(splitpath(cpl.filename)[end], io, cpl.mime)
    end
    return ios, res
end
_tomultipart(cpl::CordraPayload) = _tomultipart([cpl])
function _tomultipart(::Nothing)
    return IO[], Dict{String,HTTP.Multipart}()
end


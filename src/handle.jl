# The CordraHandle is designed to be (almost) exclusively used
# internally.  If you feel the necessity to use a CordraHandle
# ask whether you might alternatively use a CordraObject instead?
struct CordraHandle
    value::AbstractString
    connection::CordraConnection
    function CordraHandle(value::AbstractString, cc::CordraConnection)
        prefix = split(value, '/')[1]
        @assert (prefix == cc.prefix) || (startswith(prefix, "\"") && (prefix[2:end] == cc.prefix)) "Prefix does not match connection's prefix"
        new(value, cc)
    end
end

Base.show(io::IO, ch::CordraHandle) = #
    print(io, "CordraHandle($(ch.value))")

function get_object(
    handle::CordraHandle
)
    cc, hdl = handle.connection, handle.value
    params = Dict{String,Any}("full" => true)
    uri = URI(parse(URI, "$(cc.host)/objects/$hdl"), query=params)
    response = CordraResponse(HTTP.get(uri, auth(cc); require_ssl_verification=cc.verify, status_exception=false))
    return CordraObject(response, cc)
end

function delete_object(handle::CordraHandle; params=Dict{String,Any}())::Bool
    cc = handle.connection
    uri = URI(parse(URI, "$(cc.host)/objects/$(handle.value)"), query=params)
    r = _json(CordraResponse(HTTP.delete(uri, auth(cc); require_ssl_verification=cc.verify, status_exception=false)))
    if !isempty(r)
        if isnothing(jsonPointer)
            error("There was an error deleting $handle")
        else
            error("There was an error deleting $jsonPointer from $handle")
        end
    end
    return true
end

function payloads(
    handle::CordraHandle
)::Vector{Dict{String,Any}}
    # Getting CordraConnection and handle
    cc, hdl = handle.connection, handle.value
    uri = URI(parse(URI, "$(cc.host)/objects/$hdl"), query=Dict{String,Any}("full" => true))
    r = _json(CordraResponse(HTTP.get(uri, auth(cc); require_ssl_verification=cc.verify, status_exception=false)))
    get(r, "payloads", Vector{Dict{String,Any}}())
end

function delete_payload(
    handle::CordraHandle,
    payload::AbstractString
)::Bool
    @assert payload in payload_names(handle) "Invalid payload name"
    cc = handle.connection
    params = Dict{String,Any}()
    params["payload"] = payload
    uri = URI(parse(URI, "$(cc.host)/objects/$(handle.value)"), query=params)
    r = _json(CordraResponse(HTTP.delete(uri, auth(cc); require_ssl_verification=cc.verify, status_exception=false)))
    isempty(r) || error("There was an error deleting payload $payload from $handle")
    return true
end

function export_payload(
    handle::CordraHandle,
    payload::AbstractString,
    filename::Union{Nothing,AbstractString}=nothing
)
    filename = something(
        filename,
        tempname()  # A temporary file that will be cleaned up automatically upon process termination
    )
    open(filename, "w") do f
        write(f, read_payload(handle, payload))
    end
    return filename
end

function read_payload(
    handle::CordraHandle,
    payload::AbstractString
)::Vector{UInt8}
    cc, hdl = handle.connection, handle.value
    uri = URI(parse(URI, "$(cc.host)/objects/$hdl"), query=Dict{String,Any}("payload" => payload))
    return CordraResponse(HTTP.get(uri, auth(cc); require_ssl_verification=cc.verify, status_exception=false)).body
end
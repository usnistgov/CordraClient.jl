module CordraClient

using HTTP
using Reexport
using JSON
using URIs

# The external interface to the CordraClient package
export CordraConnection
export create_object
export read_object
export read_payload_info
export read_payload
export update_object
export delete_object
export find_object
export read_token

"""
A `CordraConnection` uses a username and password to construct a token which
will be used to access a Cordra host.
"""
struct CordraConnection
    host::String # URL of host
    token::String # Authentication token
    verify::Bool # Require SSL verification?

    function CordraConnection(host::AbstractString, username::AbstractString, password::AbstractString; verify::Bool=true, full::Bool=false)
        auth_json = Dict{String, Any}( 
            "grant_type" => "password",
            "username" => username,
            "password" => password
        )
        r = _json(check_response(HTTP.request(
            "POST", 
            URI(parse(URI, "$host/auth/token"), query = Dict{String, Any}( "full" => full)), 
            ["Content-type" => "application/json"], 
            JSON.json(auth_json), 
            require_ssl_verification = verify, 
            status_exception = true # question
        )))
        new(host, r["access_token"], verify)
    end
end

function Base.open(f::Function, ::Type{CordraConnection}, host::AbstractString, username::AbstractString, password::AbstractString; verify::Bool=true, full::Bool=false)
    cc = CordraConnection(host, username, password; verify=verify, full=full)
    try
        f(cc)
    catch
        rethrow()
    finally
        close(cc)
    end
end

# Helper to convert UInt8[] to JSON
_json(r) = JSON.parse(String(copy(r)))

function Base.open(::Type{CordraConnection}, host::AbstractString, username::AbstractString, password::AbstractString; verify::Bool=true, full::Bool=false)
    return CordraConnection(host, username, password, verify=verify, full=full)
end

function Base.open(f::Function, ::Type{CordraConnection}, file="config.json"; verify::Bool=true, full::Bool=false)
    config = JSON.parsefile(file)
    open(f, CordraConnection, config["host"], config["username"], config["password"], verify=verify, full=full)
end

function Base.close(cc::CordraConnection)
    return HTTP.request(
            "POST", 
            "$(cc.host)/auth/revoke", 
            ["Content-type" => "application/json"], 
            JSON.json(Dict{String, Any}( "token" => cc.token )), 
            require_ssl_verification = cc.verify, 
            status_exception = false
    )
end

auth(cc::CordraConnection) = ["Authorization" => "Bearer $(cc.token)"]

# Checks for errors and only returns the response.body if there are none
function check_response(response)
    if response.status > 400
        @show response.body
        error(string(copy(response.status)) *" "* HTTP.Messages.statustext(response.status))
    end
    response.body
end

"""
    create_object(
        cc::CordraConnection,
        obj_json=nothing,
        obj_type=nothing;
        handle=nothing,
        suffix=nothing,
        dryRun = false,
        full = false,
        payloads = nothing,
        acls = nothing
        )

Create a Cordra database object.  Syntax for payloads: `["FileDescription" => ["FileName", open("path")]]`
    
"""
function create_object(
    cc::CordraConnection,
    obj_id::AbstractString,
    obj_json::Dict{String,<:Any},
    obj_type::AbstractString;
    suffix = nothing, # I don't know what this does????
    dryRun::Bool = false,
    full::Bool = false,
    payloads = nothing,
    acls = nothing
)::Dict{String, Any}
    # Set up uri with params
    params = Dict{String, Any}(
        "type" => obj_type, 
        "handle" => obj_id
    )
    (!isnothing(suffix)) && (params["suffix"] = suffix)
    dryRun && (params["dryRun"] = true)
    (full || (!isnothing(acls))) && (params["full"] = true)
    uri = URI(parse(URI,"$(cc.host)/objects"), query=params)
    # Build the data with acl
    data = Dict{String, Any}( "content" => JSON.json(obj_json))
    (!isnothing(acls)) && (data["acl"] = JSON.json(acls))
    if !isnothing(payloads)
        for (x,y) in payloads
            data[x] = HTTP.Multipart(y[1], y[2])
        end
    end
    # Post the object
    return _json(check_response(HTTP.post(uri, auth(cc), HTTP.Form(data); require_ssl_verification = cc.verify, status_exception = false)))
end

""" 
    read_object(
        cc::CordraConnection,
        obj_id;
        jsonPointer=nothing,
        jsonFilter=nothing,
        full=false
    )::Vector{UInt8}

Retrieve a Cordra Object JSON by identifier.  The `jsonPointer` and `jsonFilter` parameters can be used to
only retrieve parts of an object.

Converting the result into an object of the appropriate type depends on the object data.  The method returns
a `Vector{UInt8}` which can be converted to:
    * String -> String(res)
    * Dict{String, Any} from JSON -> JSON.parse(String(res))
    * Float64, Int32, etc -> reinterpret(Float64, res) 
"""
function read_object(
    cc::CordraConnection,
    obj_id::AbstractString;
    jsonPointer=nothing,
    jsonFilter=nothing,
    full=false
)::Vector{UInt8}
    params = Dict{String, Any}("full" => full)
    (!isnothing(jsonPointer)) && (params["jsonPointer"] = jsonPointer)
    (!isnothing(jsonFilter)) && (params["jsonFilter"] = string(jsonFilter))
    uri = URI(parse(URI,"$(cc.host)/objects/$obj_id"), query=params)
    return check_response(HTTP.get(uri, auth(cc); require_ssl_verification = cc.verify, status_exception = false))
end

""" 
    read_payload_info(
        cc::CordraConnection,
        obj_id
    )

Retrieve a Cordra object payload names by identifier.
"""
function read_payload_info(
    cc::CordraConnection,
    obj_id
    )
    uri = URI(parse(URI,"$(cc.host)/objects/$obj_id"), query=Dict{String, Any}("full" => true))
    r = _json(check_response(HTTP.get(uri, auth(cc); require_ssl_verification = cc.verify, status_exception = false)))
    return r["payloads"]
end

""" 
    read_payload(
        cc::CordraConnection,
        obj_id,
        payload
        )

Retrieve a Cordra object payload by identifier and payload name.
"""
function read_payload(
    cc::CordraConnection,
    obj_id::AbstractString,
    payload::AbstractString
)::Vector{UInt8}
    uri = URI(parse(URI,"$(cc.host)/objects/$obj_id"), query=Dict{String, Any}( "payload" => payload))
    return check_response(HTTP.get(uri, auth(cc); require_ssl_verification = cc.verify, status_exception = false))
end

"""
    update_object(
        cc::CordraConnection,
        obj_id;
        obj_json=nothing,
        jsonPointer=nothing,
        obj_type=nothing,
        dryRun=false,
        full=false,
        payloads=nothing,
        payloadToDelete=nothing,
        acls=nothing
        )

Update a Cordra object.
"""
function update_object(
    cc::CordraConnection,
    obj_id::AbstractString;
    obj_json=nothing,
    jsonPointer=nothing,
    obj_type=nothing,
    dryRun=false,
    full=false,
    payloads=nothing,
    payloadToDelete=nothing,
    acls=nothing
)::Dict{String, Any}
    """ Update a Cordra object """
    params = Dict{String, Any}( "full" => full)
    (!isnothing(obj_type)) && (params["type"] = obj_type)
    dryRun && (params["dryRun"] = true)
    (!isnothing(jsonPointer)) && (params["jsonPointer"] = jsonPointer)
    (!isnothing(payloadToDelete)) && (params["payloadToDelete"] = payloadToDelete)

    uri = URI(parse(URI,"$(cc.host)/objects/$obj_id"), query=params)
    if !isnothing(payloads) #multi-part request        
        isnothing(obj_json) && error("obj_json is required when updating payload")
        # Construct the body
        data = Dict{String, Any}( "content" => JSON.json(obj_json))
        (!isnothing(acls)) || (data["acl"] = JSON.json(acls)) 
        for (x,y) in payloads
            data[x] = HTTP.Multipart(y[1], y[2])
        end
        body = HTTP.Form(data; boundary = "cordra") #specify boundary
        #HTTP issue: need to specify boundary
        headers = ["Content-Type" => "multipart/form-data; boundary=cordra", auth(cc)... ]
        return _json(check_response(HTTP.put(uri, headers, body; require_ssl_verification = cc.verify, status_exception = false)))
    elseif !isnothing(acls) #just update ACLs
        uri = URI(host = cc.host, path = "acls/$obj_id", query=params)
        return _json(check_response(HTTP.put(uri, auth(cc), JSON.json(acls); require_ssl_verification = cc.verify, status_exception = false)))
    else #just update object
        isnothing(obj_json) && error("obj_json is required")
        return _json(check_response(HTTP.put(uri, auth(cc), JSON.json(obj_json); require_ssl_verification = cc.verify, status_exception = false)))
    end
end

""" Delete a Cordra Object """
function delete_object(
    cc::CordraConnection,
    obj_id::AbstractString;
    jsonPointer=nothing
)
    params = Dict{String, Any}()
    (!(isnothing(jsonPointer))) && (params["jsonPointer"] = jsonPointer)
    uri = URI(parse(URI,"$(cc.host)/objects/$obj_id"), query=params)
    return _json(check_response(HTTP.delete(uri, auth(cc); require_ssl_verification = cc.verify, status_exception = false)))
end

""" Find a Cordra object by query """
function find_object(
    cc::CordraConnection,
    query::AbstractString;
    ids=nothing,
    jsonFilter=nothing,
    full=false
)
    params = Dict{String, Any}( 
        "query" => query,
        "full" => full
    )
    if !isnothing(jsonFilter)
        params["filter"] = string(jsonFilter)
    end
    if !isnothing(ids)
        params["ids"] = true
    end
    uri = URI(parse(URI,"$(cc.host)/objects/"), query=params)
    return _json(check_response(HTTP.get(uri, auth(cc); require_ssl_verification = cc.verify, status_exception = false)))
end

""" 
    read_token( cc::CordraConnection; full::Bool=false)

Get the properties ("userId", "active", "username" etc) associated with the current authentication token in `cc`.
"""
function read_token(
    cc::CordraConnection;
    full::Bool=false
)
    params = Dict{String, Any}("full" => full)
    auth_json = Dict{String, Any}("token" => cc.token)
    uri = URI(parse(URI,"$(cc.host)/auth/introspect"), query = params)
    return _json(check_response(HTTP.request("POST", uri, 
        ["Content-type" => "application/json"], JSON.json(auth_json), require_ssl_verification = cc.verify, status_exception = false)))
end

end
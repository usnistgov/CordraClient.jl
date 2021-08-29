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
export delete_payload


"""
A `CordraConnection` uses a username and password to construct a token which
will be used to access a Cordra host.
"""
struct CordraConnection #suggestion: username
    host::String # URL of host
    username::String # Username
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
        new(host, r["username"], r["access_token"], verify)
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
        (!isempty(response.body)) && @show _json(response.body)["message"]
        error(string(copy(response.status)) *" "* HTTP.Messages.statustext(response.status))
    end
    response.body
end

"""
    create_object(
        cc::CordraConnection,
        obj_id::AbstractString,        # the object's ID
        obj_json::Dict{String,<:Any},  # the object's JSON data.
        obj_type::AbstractString;      # the object's data schema name.
        suffix=nothing,
        dryRun = false,                # Don't actually add the item
        full = false,                  # Return meta-data in addition to object data
        payloads = nothing,            # payload data (like binary or file data)
        acls = nothing                 # Access control lists as a Dict{String, Any}
    )

Create a Cordra database object. 

Syntax for `payloads`: 

    ["FileDescription" => HTTP.Multipart("name",io,"mime/type")]
    ["FileDescription" => ("name",io,"mime/type")]
    Dict("FileDescription" => ("name",io,"mime/type"))
    Dict("FileDescription" => ("name",io))
    Dict("FileDescription" => ["name",io])
    Dict("FileDescription" => HTTP.Multipart("name",io,"mime/type"))

or similar where `io` is an `IOStream`.
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
    # Interpreting payload
    _mp(y) = HTTP.Multipart(y...)
    _mp(y::HTTP.Multipart) = y
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
            data[x] = _mp(y)
        end
    end
    # Post the object
    return _json(check_response(HTTP.post(uri, auth(cc), HTTP.Form(data); require_ssl_verification = cc.verify, status_exception = false)))
end

""" 
    read_object(
        cc::CordraConnection,
        obj_id;                 # The object ID
        jsonPointer=nothing,    # An optional name of an item in the object
        jsonFilter=nothing,     # An optional filter to items in the object
        full=false              # Return meta-data in addition to object data?
    )::Vector{UInt8}

Retrieve a Cordra Object JSON by identifier.  The `jsonPointer` and `jsonFilter` parameters can be used to
only retrieve parts of an object.

Converting the result into an object of the appropriate type depends on the object data.  The method returns
a `Vector{UInt8}` which can be converted to:
    * String -> String(copy(res))
    * Dict{String, Any} from JSON -> JSON.parse(String(copy(res)))
    * Float64, Int32, etc -> reinterpret(Float64, res) 
"""
function read_object( #Discuss interpretations
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

See the create_object(...) documentation for details on `payloads`
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
    acls=nothing
)::Dict{String, Any}
    # Interpreting payload
    _mp(y) = HTTP.Multipart(y...)
    _mp(y::HTTP.Multipart) = y
    # Configure params
    params = Dict{String, Any}( "full" => full)
    (!isnothing(obj_type)) && (params["type"] = obj_type)
    dryRun && (params["dryRun"] = true)
    (!isnothing(jsonPointer)) && (params["jsonPointer"] = jsonPointer)
    (!isnothing(payloads)) && (params["full"] = true)

    uri = URI(parse(URI,"$(cc.host)/objects/$obj_id"), query=params)
    if !isnothing(payloads) #multi-part request
        (!isnothing(jsonPointer)) && error("Cannot specify jsonPointer and payloads")
        # Construct the body
        if !isnothing(obj_json)
            data = Dict{String, Any}( "content" => JSON.json(obj_json)) 
        else
            data = Dict{String, Any}( "content" => JSON.json(_json(read_object(cc, obj_id)))) # keep original object JSON if one is not provided
        end
        (!isnothing(acls)) && (data["acl"] = JSON.json(acls)) 
        for (x,y) in payloads
            data[x] = _mp(y)
        end
        body = HTTP.Form(data; boundary = "cordra") #specify boundary
        #HTTP issue: need to specify boundary
        headers = ["Content-Type" => "multipart/form-data; boundary=cordra", auth(cc)... ]
        return _json(check_response(HTTP.put(uri, headers, body; require_ssl_verification = cc.verify, status_exception = false)))
    elseif !isnothing(acls) #just update ACLs
        uri = URI(parse(URI,"$(cc.host)/acls/$obj_id"), query=params)
        return _json(check_response(HTTP.put(uri, auth(cc), JSON.json(acls); require_ssl_verification = cc.verify, status_exception = false)))
    else #just update object
        isnothing(obj_json) && error("obj_json is required")
        if !isnothing(jsonPointer)
            return Dict([string(strip(jsonPointer, ['/'])) => _json(check_response(HTTP.put(uri, auth(cc), JSON.json(obj_json); require_ssl_verification = cc.verify, status_exception = false)))])
        else
            return _json(check_response(HTTP.put(uri, auth(cc), JSON.json(obj_json); require_ssl_verification = cc.verify, status_exception = false)))
        end
    end
end

"""
    delete_object(
        cc::CordraConnection,
        obj_id::AbstractString;   # The object ID
        jsonPointer=nothing       
        )
If `jsonPointer` is specified, instead of deleting the object, only the content at the specified JSON pointer will be deleted (including the pointer itself).

Delete a Cordra Object.
"""
function delete_object(
    cc::CordraConnection,
    obj_id::AbstractString;
    jsonPointer=nothing
)
    params = Dict{String, Any}()
    if !isnothing(jsonPointer)
        read_object(cc, obj_id, jsonPointer = jsonPointer) # Throws error if jsonPointer not found
        params["jsonPointer"] = jsonPointer
    end
    uri = URI(parse(URI,"$(cc.host)/objects/$obj_id"), query=params)
    r = _json(check_response(HTTP.delete(uri, auth(cc); require_ssl_verification = cc.verify, status_exception = false)))
    if isempty(r) # test this. I cannot come up with a case where this would not work
        if isnothing(jsonPointer)
            println("Succesfully deleted object with id $obj_id")
            return r
        else
            println("Succesfully deleted $jsonPointer from object with id $obj_id")
            return r
        end
    else
        return r
    end
        
end

"""
    delete_payload(
        cc::CordraConnection,
        obj_id,              # The object ID
        payload              # The name of the payload to delete
        )

Delete a payload from a Cordra object.
"""
function delete_payload(
    cc::CordraConnection,
    obj_id::AbstractString,
    payload::AbstractString
)
    read_payload(cc, obj_id, payload) # Throws error if payload not found
    params = Dict{String, Any}()
    params["payload"] = payload
    uri = URI(parse(URI,"$(cc.host)/objects/$obj_id"), query=params) 
    r = _json(check_response(HTTP.delete(uri, auth(cc); require_ssl_verification = cc.verify, status_exception = false)))
    if isempty(r) # test this. I cannot come up with a case where this would not work
        println("Succesfully deleted $payload from object with id $obj_id")
        return r
    else
        return r
    end
end

""" 
    find_object(
        cc::CordraConnection,
        query::AbstractString;
        ids::Bool=false,      # If true, the search returns the ids of the matched objects only.
        jsonFilter=nothing,   # An optional filter to items in the object
        full::Bool=false,     # Return meta-data in addition to object data?
        pageNum::Int=0,       # The desired results page number. 0 is the first page
        pageSize::Int=10      
        )
    
`pageSize` defines the number of results per page. If negative no limit. If 0 no results are returned, only the size (number of hits).

Find a Cordra object by query.
"""
function find_object(
    cc::CordraConnection,
    query::AbstractString;
    ids::Bool=false,
    jsonFilter=nothing,
    full::Bool=false,
    pageNum::Int=0,
    pageSize::Int=10
)
    params = Dict{String, Any}( 
        "query" => query,
        "ids" => ids,
        "full" => full,
        "pageNum" => pageNum,
        "pageSize" => pageSize
    )
    (!isnothing(jsonFilter)) && (params["filter"] = string(jsonFilter))
    uri = URI(parse(URI,"$(cc.host)/objects/"), query=params)
    return _json(check_response(HTTP.get(uri, auth(cc); require_ssl_verification = cc.verify, status_exception = false))) #not working well
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
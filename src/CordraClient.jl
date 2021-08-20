module CordraClient

using HTTP
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

    function CordraConnection(host, username, password; verify::Bool=true, full::Bool=false)
        auth_json = Dict{String, Any}( 
            "grant_type" => "password",
            "username" => username,
            "password" => password
        )
        r = check_response(HTTP.request(
            "POST", 
            URI(parse(URI, "$host/auth/token"), query = Dict{String, Any}( "full" => full)), 
            ["Content-type" => "application/json"], 
            JSON.json(auth_json), 
            require_ssl_verification = verify, 
            status_exception = true
        ))
        new(host, r["access_token"], verify)
    end
end

function Base.open(f::Function, ::Type{CordraConnection}, host, username, password; verify::Bool=true, full::Bool=false)
    cc = CordraConnection(host, username, password; verify=verify, full=full)
    try
        f(cc)
    catch
        rethrow()
    finally
        close(cc)
    end
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

function check_response(response)
    if response.status < 400
        return JSON.parse(String(copy(response.body)))
    else
        println(String(copy(response.body)))
        error(string(copy(response.status)) *" "* HTTP.Messages.statustext(response.status))
    end
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

Create a Cordra database object.
"""
function create_object(
    cc::CordraConnection,
    obj_json,
    obj_type;
    handle=nothing,
    suffix=nothing,
    dryRun = false,
    full = false,
    payloads = nothing,
    acls = nothing
)
    params = Dict{String, Any}("type" => obj_type)
    if !isnothing(handle)
        params["handle"] = handle
    end
    if !isnothing(suffix)
        params["suffix"] = suffix
    end
    if dryRun
        params["dryRun"] = dryRun
    end
    if full
        params["full"] = full
    end
    if !isnothing(acls)
        params["full"] = true
    end
    uri = URI(parse(URI,"$(cc.host)/objects"), query=params)
    #payloads syntax ["FileDescription" => ["FileName", IOStream-open("path")-]]
    if !isnothing(payloads)
        data = Dict{String, Any}( "content" => JSON.json(obj_json))
        if !isnothing(acls)
            data["acl"] = JSON.json(acls)
        end
        for (x,y) in payloads
            data[x] = HTTP.Multipart(y[1], y[2])
        end
        body = HTTP.Form(data)
        return check_response(HTTP.post(uri, auth(cc), body; require_ssl_verification = cc.verify, status_exception = false))
    else
        if !isnothing(acls) #ACLs, no payloads. Multi-part request
            body = HTTP.Form(
                Dict{String, Any}( 
                    "content" => JSON.json(obj_json),
                    "acl" => JSON.json(acls)
                )
            )    
            r = check_response(HTTP.post(uri, auth(cc), body; require_ssl_verification = cc.verify, status_exception = false))
            return r
        else #simple request. No ACLs, no payloads
            return check_response(HTTP.post(uri, auth(cc), JSON.json(obj_json); require_ssl_verification = cc.verify, status_exception = false))
        end
    end
end

""" 
    read_object(
        cc::CordraConnection,
        obj_id;
        jsonPointer=nothing,
        jsonFilter=nothing,
        full=false
        )

Retrieve a Cordra Object JSON by identifier 
"""
function read_object(
    cc::CordraConnection,
    obj_id;
    jsonPointer=nothing,
    jsonFilter=nothing,
    full=false
    )
    params = Dict{String, Any}("full" => full)
    if !isnothing(jsonPointer)
        params["jsonPointer"] = jsonPointer
    end
    if !isnothing(jsonFilter)
        params["jsonFilter"] = string(jsonFilter)
    end
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
    r = check_response(HTTP.get(uri, auth(cc); require_ssl_verification = verify, status_exception = false))
    return r["payloads"]
end

""" Retrieve a Cordra object payload by identifier and payload name """
function read_payload(
    cc::CordraConnection,
    obj_id,
    payload
)
    uri = URI(parse(URI,"$(cc.host)/objects/$obj_id"), query=Dict{String, Any}( "payload" => payload))
    return check_response(HTTP.get(uri, auth(cc); require_ssl_verification = verify, status_exception = false))
end

function update_object(
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
    """ Update a Cordra object """
    params = Dict{String, Any}()
    if !isnothing(obj_type)
        params["type"] = obj_type
    end
    if !isnothing(dryRun)
        params["dryRun"] = dryRun
    end
    if !isnothing(full)
        params["full"] = full
    end
    if !isnothing(jsonPointer)
        params["jsonPointer"] = jsonPointer
    end
    if !isnothing(payloadToDelete)
        params["payloadToDelete"] = payloadToDelete
    end
    uri = URI(parse(URI,"$(cc.host)/objects/$obj_id"), query=params)
    if !isnothing(payloads) #multi-part request
        #HTTP issue: need to specify boundary
        headers = ["Content-Type" => "multipart/form-data; boundary=cordra", auth(cc)... ]
        if isnothing(obj_json)
            error("obj_json is required when updating payload")
        end
        data = Dict{String, Any}(
            "content" => JSON.json(obj_json),
            "acl" => JSON.json(acls)
        )
        for (x,y) in payloads
            data[x] = HTTP.Multipart(y[1], y[2])
        end
        body = HTTP.Form(data; boundary = "cordra") #specify boundary
        return check_response(HTTP.put(uri, headers, body; require_ssl_verification = verify, status_exception = false))
    elseif !isnothing(acls) #just update ACLs
        uri = URI(host = cc.host, path = "acls/$obj_id", query=params)
        return check_response(HTTP.put(uri, auth(cc), JSON.json(acls); require_ssl_verification = verify, status_exception = false))
    else #just update object
        if isnothing(obj_json)
            error("obj_json is required")
        end
        return check_response(HTTP.put(uri, auth(cc), JSON.json(obj_json); require_ssl_verification = verify, status_exception = false))
    end
end

""" Delete a Cordra Object """
function delete_object(
    cc::CordraConnection,
    obj_id;
    jsonPointer=nothing
)
    params = Dict{String, Any}()
    if !(isnothing(jsonPointer))
        params["jsonPointer"] = jsonPointer
    end
    uri = URI(parse(URI,"$(cc.host)/objects/$obj_id"), query=params)
    return check_response(HTTP.delete(uri, auth(cc); require_ssl_verification = verify, status_exception = false))
end

""" Find a Cordra object by query """
function find_object(
    cc::CordraConnection,
    query;
    ids=false,
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
    return check_response(HTTP.get(uri, auth(cc); require_ssl_verification = verify, status_exception = false))
end

""" Read an access Token """
function read_token(
    cc::CordraConnection;
    full=false
)
    params = Dict{String, Any}("full" => full)
    auth_json = Dict{String, Any}("token" => cc.token)
    uri = URI(parse(URI,"$(cc.host)/auth/introspect"), query = params)
    return check_response(HTTP.request("POST", uri, 
        ["Content-type" => "application/json"], JSON.json(auth_json), require_ssl_verification = verify, status_exception = false))
end

""" Check connection to Cordra """
function check_connection(
    host = "https://localhost:8443";
    verify = false
)
    try
        HTTP.get(host, []; require_ssl_verification = verify, retry = false)
        println("Success")
    catch
        throw(error("Could not connect to $host"))
    end
end

end

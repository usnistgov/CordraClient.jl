module CordraClient

using HTTP
using JSON
using Base64
using URIs

""" Global variables """
const objects_endpoint = "objects/"
const acls_endpoint = "acls/"
const token_create_endpoint = "auth/token"
const token_read_endpoint = "auth/introspect"
const token_delete_endpoint = "auth/revoke"
const token_grant_type = "password"
const token_type = "Bearer"

""" General functions used to check HTTP respones, create headers, create urls specific to Cordra """
function endpoint_url(host, endpoint)
    return strip(host, ['/']) * '/' * endpoint
end

#Mimicking Python requests' raise_for_status
function response_ok(response)
    if response.status < 400
        return true
    else
        return false
    end
end

function raise_for_status(response)
    if !(response_ok(response))
        return println(string(copy(response.status)) *" "* HTTP.Messages.statustext(response.status))
    else
        return nothing
    end
end

function set_auth(username=nothing, password=nothing)
    if !(isnothing(username)) && !(isnothing(password))
        auth = Base64.base64encode(username * ":" * password)
    else
        auth = nothing
    end
    return auth
end

function set_headers(username=nothing, password=nothing, token = nothing)
    if isnothing(token)
        return ["Authorization" => "Basic $(set_auth(username, password))"]
    else
        return ["Authorization" => "$(token_type) $(get_token_value(token))"]
    end
end

function check_response(response)
    if !(response_ok(response))
        try
            println(String(copy(response.body)))
        catch e
            print(String(copy(response.body)))
        end
        raise_for_status(response)
        return nothing
    else
        try
            return JSON.parse(String(copy(response.body)))
        catch e
            return String(copy(response.body))
        end
    end
end

function get_token_value(token)
    if token isa String
        return token
    elseif token isa Dict
        try
            return token["access_token"]
        catch
            error("Token JSON format error")
        end
    else
        error("Token format error")
    end
end

"""Functions to work with Cordra objects"""

function CreateObject(
    host,
    obj_json=nothing,
    obj_type=nothing,
    ;handle=nothing,
    suffix=nothing,
    dryRun = false,
    username=nothing,
    password=nothing,
    token = nothing,
    verify=nothing,
    full = false,
    payloads = nothing,
    acls = nothing
    )
    """ Create a Cordra Object """
    params = Dict()
    params["type"] = obj_type
    if !(isnothing(handle))
        params["handle"] = handle
    end
    if !(isnothing(suffix))
        params["suffix"] = suffix
    end
    if dryRun
        params["dryRun"] = dryRun
    end
    if full
        params["full"] = full
    end

    if !(isnothing(acls))
        params["full"] = true
    end

    uri = URI(endpoint_url(host, objects_endpoint))
    uri = URI(uri; query=params)
    headers = set_headers(username, password, token)

    #payloads syntax ["FileDescription" => ["FileName", IOStream-open("path")-]]
    """ Payloads and optional ACLs. Multi-part request """
    if !(isnothing(payloads))
        data = Dict()
        data["content"] = JSON.json(obj_json)
        if !(isnothing(acls))
            data["acl"] = JSON.json(acls)
        end
        for (x,y) in payloads
            data[x] = HTTP.Multipart(y[1], y[2])
        end
        body = HTTP.Form(data)
        r = check_response(HTTP.post(uri, headers, body; require_ssl_verification = verify, status_exception = false))
        return r

     
    else
        
        if !(isnothing(acls))#ACLs, no payloads. Multi-part request
            data = Dict()
            data["content"] = JSON.json(obj_json)
            data["acl"] = JSON.json(acls)
            body = HTTP.Form(data)
            r = check_response(HTTP.post(uri, headers, body; require_ssl_verification = verify, status_exception = false))
            return r
        else #simple request. No ACLs, no payloads
            data = JSON.json(obj_json)
            r = check_response(HTTP.post(uri, headers, data; require_ssl_verification = verify, status_exception = false))
            return r
        end
    end
end

function ReadObject(
    host,
    obj_id,
    ;username=nothing,
    password=nothing,
    token=nothing,
    verify=nothing,
    jsonPointer=nothing,
    jsonFilter=nothing,
    full=false
    )
    """ Retrieve a Cordra Object JSON by identifier """
    params = Dict()
    params["full"] = full
    if !(isnothing(jsonPointer))
        params["jsonPointer"] = jsonPointer
    end
    if !(isnothing(jsonFilter))
        params["jsonFilter"] = string(jsonFilter)
    end
    uri = URI(endpoint_url(host, objects_endpoint) * obj_id)
    uri = URI(uri; query=params)
    headers = set_headers(username, password, token)
    r = check_response(HTTP.get(uri, headers; require_ssl_verification = verify, status_exception = false))
    return r
end

function ReadPayloadInfo(
    host,
    obj_id,
    ;username=nothing,
    password=nothing,
    token=nothing,
    verify=nothing
    )
    """ Retrieve a Cordra object payload names by identifier """
    params = Dict()
    params["full"] = true
    uri = URI(endpoint_url(host, objects_endpoint) * obj_id)
    uri = URI(uri; query=params)
    headers = set_headers(username, password, token)
    r = check_response(HTTP.get(uri, headers; require_ssl_verification = verify, status_exception = false))
    return r["payloads"]
end

function ReadPayload(
    host,
    obj_id,
    payload,
    ;username=nothing,
    password=nothing,
    token=nothing,
    verify=nothing
    )
    """ Retrieve a Cordra object payload by identifier and payload name """
    params = Dict()
    params["payload"] = payload
    uri = URI(endpoint_url(host, objects_endpoint) * obj_id)
    uri = URI(uri; query=params)
    headers = set_headers(username, password, token)
    r = check_response(HTTP.get(uri, headers; require_ssl_verification = verify, status_exception = false))
    return r
end

function UpdateObject(
    host,
    obj_id,
    ;obj_json=nothing,
    jsonPointer=nothing,
    obj_type=nothing,
    dryRun=false,
    username=nothing,
    password=nothing,
    token=nothing,
    verify=nothing,
    full=false,
    payloads=nothing,
    payloadToDelete=nothing,
    acls=nothing
    )
    """ Update a Cordra object """
    params = Dict()
    if !(isnothing(obj_type))
        params["type"] = obj_type
    end
    if !(isnothing(dryRun))
        params["dryRun"] = dryRun
    end
    if !(isnothing(full))
        params["full"] = full
    end
    if !(isnothing(jsonPointer))
        params["jsonPointer"] = jsonPointer
    end
    if !(isnothing(payloadToDelete))
        params["payloadToDelete"] = payloadToDelete
    end
    
    uri = URI(endpoint_url(host, objects_endpoint)*obj_id)
    uri = URI(uri; query=params)
    headers = set_headers(username, password, token)
    if !(isnothing(payloads)) #multi-part request
        #HTTP issue: need to specify boundary
        headers = ["Content-Type" => "multipart/form-data; boundary=cordra", (set_headers(username, password, token)[1])]
        if isnothing(obj_json)
            error("obj_json is required when updating payload")
        end
        data = Dict()
        data["content"] = JSON.json(obj_json)
        data["acl"] = JSON.json(acls)
        for (x,y) in payloads
            data[x] = HTTP.Multipart(y[1], y[2])
        end
        body = HTTP.Form(data; boundary = "cordra") #specify boundary
        r = check_response(HTTP.put(uri, headers, body; require_ssl_verification = verify, status_exception = false))
        return r
    elseif !(isnothing(acls)) #just update ACLs
        uri = URI(endpoint_url(host, acls_endpoint)*obj_id)
        uri = URI(uri; query=params)
        r = check_response(HTTP.put(uri, headers, JSON.json(acls); require_ssl_verification = verify, status_exception = false))
        return r
    else #just update object
        if isnothing(obj_json)
            error("obj_json is required")
        end
        r = check_response(HTTP.put(uri, headers, JSON.json(obj_json); require_ssl_verification = verify, status_exception = false))
        return r
    end
end

function DeleteObject(
    host,
    obj_id,
    ;jsonPointer=nothing,
    username=nothing,
    password=nothing,
    token=nothing,
    verify=nothing
    )
    """ Delete a Cordra Object """

    params = Dict()
    if !(isnothing(jsonPointer))
        params["jsonPointer"] = jsonPointer
    end
    uri = URI(endpoint_url(host, objects_endpoint) * obj_id)
    uri = URI(uri; query=params)
    headers = set_headers(username, password, token)

    r = check_response(HTTP.delete(uri, headers; require_ssl_verification = verify, status_exception = false))
    return r
end

function FindObject(
    host,
    query,
    ;username=nothing,
    password=nothing,
    token=nothing,
    verify=nothing,
    ids=false,
    jsonFilter=nothing,
    full=false
    )
    """ Find a Cordra object by query """
    params = Dict()
    params["query"] = query
    params["full"] = full
    if !(isnothing(jsonFilter))
        params["filter"] = string(jsonFilter)
    end
    if !(isnothing(ids))
        params["ids"] = true
    end
    uri = URI(endpoint_url(host, objects_endpoint))
    uri = URI(uri; query=params)
    headers = set_headers(username, password, token)
    r = check_response(HTTP.get(uri, headers; require_ssl_verification = verify, status_exception = false))
    return r
end

"""Tokens """

function CreateToken(
    host,
    username,
    password,
    ;verify=nothing,
    full=false
    )
    """ Create an access Token """
    params = Dict()
    params["full"] = full
    auth_json = Dict()
    auth_json["grant_type"] = token_grant_type
    auth_json["username"] = username
    auth_json["password"] = password
    
    uri = URI(endpoint_url(host, token_create_endpoint))
    uri = URI(uri; query = params)
    
    r = check_response(HTTP.request("POST", uri, 
    ["Content-type" => "application/json"], JSON.json(auth_json), require_ssl_verification = verify, status_exception = false))

    return r
end

function ReadToken(
    host,
    token,
    ;verify=nothing,
    full=false
    )
    """ Read an access Token """
    params = Dict()
    params["full"] = full

    auth_json = Dict()
    auth_json["token"] = get_token_value(token)

    uri = URI(endpoint_url(host, token_read_endpoint))
    uri = URI(uri; query = params)

    r = check_response(HTTP.request("POST", uri, 
    ["Content-type" => "application/json"], JSON.json(auth_json), require_ssl_verification = verify, status_exception = false))

    return r
end

function DeleteToken(
    host,
    token,
    ;verify=nothing,
    )
    """ Delete an access Token """

    auth_json = Dict()
    auth_json["token"] = get_token_value(token)

    uri = URI(endpoint_url(host, token_delete_endpoint))

    r = check_response(HTTP.request("POST", uri, 
    ["Content-type" => "application/json"], JSON.json(auth_json), require_ssl_verification = verify, status_exception = false))

    return r
end

""" Check connection to Cordra """
function CheckConnection(
    host = "https://localhost:8443",
    ;verify = false
    )
    try
        HTTP.get(host, [];require_ssl_verification = verify, retry = false)
        println("Success")
    catch
        println("Could not connect")
    end
end



end

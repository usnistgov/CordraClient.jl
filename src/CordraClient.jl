module CordraClient

using HTTP
using Reexport
using JSON
using URIs
using DataStructures
using DataFrames

# The external interface to the CordraClient package
export CordraConnection
export CordraPayload
export content
export create_object
export create_schema
export read_payload_info
export read_payload
export export_payload
export update_object
export update_acls
export delete_object
export query
export read_token
export delete_payload
export get_object
export query_ids
export nquery
export update_schema
export get_schema
export build_acls


"""
    CordraConnection(
        host::AbstractString,
        handle::AbstractString,
        username::AbstractString,
        password::Union{Nothing, AbstractString}=nothing;
        verify::Bool=true,
        full::Bool=false
    )


Uses a username and password to construct a token which will be used to access a Cordra host.

If no `password` is specified - the argument can be omitted - the user will be prompted to enter one.
It can also be used within a context manager along with a JSON config file containing `host`, `username`,
and `password`:

# Examples
```julia-repl
julia> open(CordraConnection, <path to config file>) do cc
        <execute commands here with cc as the CordraConnection object>
        create_object(cc, my_dict, "mytype")
    end
```
Note that this `CordraConnection` will only be valid inside the context manager: the `token` is deleted from Cordra once Julia closes the context manager.
"""
struct CordraConnection
    host::String # URL of host
    prefix::String # prefix of repository
    username::String # Username
    token::String # Authentication token
    verify::Bool # Require SSL verification?

    function CordraConnection(host::AbstractString, username::AbstractString, password::Union{Nothing,AbstractString}=nothing; verify::Bool=true, full::Bool=false)
        if isnothing(password)
            p = Base.getpass("Password")
            password = read(p, String)
            Base.shred!(p)
        end
        auth_json = Dict{String,Any}(
            "grant_type" => "password",
            "username" => username,
            "password" => password
        )
        r = _json(CordraResponse(HTTP.request(
            "POST",
            URI(parse(URI, "$host/auth/token"), query=Dict{String,Any}("full" => full)),
            ["Content-type" => "application/json"],
            JSON.json(auth_json),
            require_ssl_verification=verify,
            status_exception=true
        )))
        # getting prefix
        p = _json(CordraResponse(HTTP.request(
            "GET",
            "$host/design",
            [],
            JSON.json(auth_json),
            require_ssl_verification=verify,
            status_exception=true
        )))
        _prefix = p["handleMintingConfig"]["prefix"]
        new(host, _prefix, r["username"], r["access_token"], verify)
    end
end

Base.show(io::IO, cc::CordraConnection) = # 
    print(io, "CordraConnection($(cc.host)/$(cc.prefix) as $(cc.username))")

function Base.open(f::Function, ::Type{CordraConnection}, host::AbstractString, username::AbstractString, password::Union{Nothing,AbstractString}=nothing; verify::Bool=true, full::Bool=false)
    cc = CordraConnection(host, username, password; verify=verify, full=full)
    try
        f(cc)
    catch
        rethrow()
    finally
        close(cc)
    end
end


function Base.open(::Type{CordraConnection}, host::AbstractString, username::AbstractString, password::Union{Nothing,AbstractString}=nothing; verify::Bool=true, full::Bool=false)
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
        JSON.json(Dict{String,Any}("token" => cc.token)),
        require_ssl_verification=cc.verify,
        status_exception=false
    )
end

auth(cc::CordraConnection) = ["Authorization" => "Bearer $(cc.token)"]

struct CordraHandle
    value::AbstractString
    connection::CordraConnection
    function CordraHandle(value::AbstractString, cc::CordraConnection)
        prefix = split(value, '/')[1]
        @assert (prefix == cc.prefix) || (startswith(prefix, "\"") && ( prefix[2:end] == cc.prefix )) "Prefix does not match connection's prefix"
        new(value, cc)
    end
end

Base.show(io::IO, ch::CordraHandle) = #
    print(io, "CordraHandle($(ch.value))")

struct CordraResponse
    body::Vector{UInt8}
    status::Int16
    function CordraResponse(response::HTTP.Messages.Response)
        # Checks for errors and only returns the response.body if there are none
        if response.status >= 400
            if isempty(response.body)
                error(string(copy(response.status)) * " " * HTTP.Messages.statustext(response.status))
            end
            error(string(copy(response.status)) * " " * HTTP.Messages.statustext(response.status) * ". " * _json(response.body)["message"])
        end
        new(response.body, response.status)
    end
end

"""
    CordraObject(
        response::Dict{String, Any},
        handle::CordraHandle
    )

Represents a Cordra database object in Julia. 

The field `response` contains the object's metadata including its JSON content `.response["content"]`.
The field `handle` contains the Cordra handle (unique identifier) of this object in the Cordra database.
Not meant to be initialized directly, it will be returned by functions such as [`create_object`](@ref).
"""
struct CordraObject
    response::Dict{String,Any}
    handle::CordraHandle
    function CordraObject(response::Union{Dict{String,Any},Vector{UInt8}}, handle::AbstractString, cc::CordraConnection)
        handle = CordraHandle(handle, cc)
        new(response, handle)
    end
    function CordraObject(response::CordraResponse, cc::CordraConnection)
        body = _json(response.body)
        CordraObject(body, body["id"], cc)
    end
end

Base.show(io::IO, co::CordraObject) = #
    print(io, "CordraObject($(co.handle.value))")

# Helper to convert UInt8[] to JSON
_json(r::CordraResponse) = JSON.parse(String(copy(r.body)))
_json(r::Vector{UInt8}) = JSON.parse(String(copy(r)))

# Helper to get CordraConnection and handle from CordraObject
_ch(co::CordraObject) = co.handle.connection, co.handle.value

# Helper to check a handle's prefix against a CordraConnection's prefix
function _prefix(cc::CordraConnection, handle::AbstractString)
    prefix = split(handle, '/')[1]
    @assert prefix == cc.prefix || ( startswith(prefix,"\"") && prefix[2:end]==cc.prefix ) "Handle's prefix does not match connection's prefix"
end

content(co::CordraObject) = co.response["content"]

"""
    CordraPayload(filename::String, mime::String)

Construct a CordraPayload for an existing file.

Example:
```julia-repl
julia> cp1=CordraPayload("Desktop\\trialC.svg", "image/svg+xml")
julia> cp2=CordraPayload("Desktop\\GSR2020.tsv", "text/tab-separated-values")
```
"""
struct CordraPayload
    name::String
    filename::String
    mime::String
    function CordraPayload(filename::String, mime::String)
        @assert isfile(filename) "CordraPayload: $filename must be an existing file."
        name = splitpath(filename)[end]
        new(name, filename, mime)
    end
end

function _tomultipart(cpls::Vector{CordraPayload})
    res = Dict{String, HTTP.Multipart}()
    ios = IO[]
    for (i, cpl) in enumerate(cpls)
        io = open(cpl.filename, "r")
        push!(ios, io)
        res["Payload$i"] = HTTP.Multipart(cpl.name, io, cpl.mime)
    end
    return ios, res
end
_tomultipart(cpl::CordraPayload) = _tomultipart([cpl])
function _tomultipart(::Nothing)
    return IO[], Dict{String, HTTP.Multipart}()
end

"""
    create_object(
        cc::CordraConnection,
        obj_json::Union{AbstractDict, DataFrameRow},   # The object's JSON data or a DataFrame row to convert to JSON.
        obj_type::AbstractString;      # The object's data schema name.
        handle = nothing,              # The object's ID including Cordra's prefix <prefix/id>
        suffix = nothing,              # The object's ID
        dryRun = false,                # Don't actually add the item
        payloads::Union{Nothing,CordraPayload, Vector{CordraPayload}}=nothing, # Data to attach to the object
        acls = nothing                 # Access control lists
    )::CordraObject

Create a Cordra database object. Return a `CordraObject`.

The function `build_acls(...)` is useful for looking up the user and group IDs necessary for the ACL.

# Examples
```julia-repl
julia> cc = CordraConnection("https://localhost:8443", "admin", "password"; verify = false)
[...]
julia> my_dict = Dict{String, Any}(["name" => "Julia", "version" => 1.7])
Dict{String, Any} with 2 entries:
  "name"    => "Julia"
  "version" => 1.7
julia> my_type = "ProgrammingLanguage" # Cordra Object Type (schema in database)
"ProgrammingLanguage"
julia> acls = build_acls(readers=["nicholas", "camilo"], writers=["camilo"], payloadreaders=["nicholas","GFNB"])
julia> obj = create_object(cc, my_dict, my_type, acls = acls)
CordraClient.CordraObject(Dict{String, Any}("content" => Dict{String, Any}("name" => "Julia", "version" => 1.7), 
"id" => "test/11972sdb4389373", "metadata" => Dict{String, Any}("createdBy" => "admin", "modifiedBy" => "admin",
"createdOn" => 1655913009, "modifiedOn" => 16559139109), "type" => "ProgrammingLanguage"), CordraClient.CordraHandle("test/11972sdb4389373",
CordraConnection("https://localhost:8443", "test", "admin", "1c2hofadfr6heyfskug2ltwhh", false)))
julia> obj.response
Dict{String, Any} with 4 entries:
  "content"  => Dict{String, Any}("name"=>"Julia", "v…
  "id"       => "test/75702da268e6150922fc"
  "metadata" => Dict{String, Any}("createdBy"=>"admin…
  "type"     => "ProgrammingLanguage"
julia> obj.handle.value
"test/11972sdb4389373"
julia> typeof(obj)
CordraClient.CordraObject
```
"""
function create_object(
    cc::CordraConnection,
    obj_json::AbstractDict,
    obj_type::AbstractString;
    handle=nothing,
    suffix=nothing,
    dryRun::Bool=false,
    payloads::Union{Nothing,CordraPayload,Vector{CordraPayload}}=nothing,
    acls=nothing
)::CordraObject

    (isnothing(handle)) || (_prefix(cc, handle))
    # Interpreting payload
    _mp(y) = HTTP.Multipart(y...)
    _mp(y::HTTP.Multipart) = y
    # Set up uri with params
    params = Dict{String,Any}(
        "type" => obj_type
    )
    (isnothing(suffix)) || (params["suffix"] = replace(suffix, r"\s" => "_"))
    (isnothing(handle)) || (params["handle"] = replace(handle, r"\s" => "_" ))
    dryRun && (params["dryRun"] = true)
    params["full"] = true # do not change
    uri = URI(parse(URI, "$(cc.host)/objects"), query=params)
    # Build the data with acl
    data = Dict{String,Any}("content" => JSON.json(obj_json))
    (isnothing(acls)) || (data["acl"] = JSON.json(acls))
    ios, pls = _tomultipart(payloads)
    try
        merge!(data, pls)
        # Post the object
        response = CordraResponse(HTTP.post(uri, auth(cc), HTTP.Form(data); require_ssl_verification=cc.verify, status_exception=false))
        (response.status != 200) && error(_json(response)) # not successful = no CordraObject
        return CordraObject(response, cc)
    finally
        close.(ios)
    end
end

function create_object(
    cc::CordraConnection,
    obj::DataFrameRow,
    obj_type::AbstractString;
    vargs...
)
    obj_json = OrderedDict(zip(n, map(x -> getproperty(obj, x), names(obj))))
    create_object(cc, obj_json, obj_type; vargs...)
end

"""
    create_schema(
        cc::CordraConnection,
        name::AbstractString,      # The schema name.
        obj_json::AbstractDict,        # The schema's JSON data.
    )::Bool

Create a Cordra schema definition. Return `true` if successful.

"""
function create_schema(
    cc::CordraConnection,
    name::AbstractString,
    obj_json::AbstractDict,
)::Bool
    uri = URI(parse(URI, "$(cc.host)/schemas/$(name)"))
    (nquery(cc, "type:\"Schema\" AND /name:\"$(name)\"") == 0) || error("Schema $(name) already exists, use update_schema instead")

    CordraResponse(HTTP.put(uri, auth(cc), JSON.json(obj_json), require_ssl_verification=cc.verify, status_exception=false))

    return true
end

"""
    update_schema(
        cc::CordraConnection,
        name::AbstractString,      # The schema name.
        obj_json::AbstractDict,        # The schema's JSON data.
    )::Bool

Update a Cordra schema definition. Return `true` if successful.

"""
function update_schema(
    cc::CordraConnection,
    name::AbstractString,
    obj_json::AbstractDict,
)::Bool
    uri = URI(parse(URI, "$(cc.host)/schemas/$(name)"))
    (nquery(cc, "type:\"Schema\" AND /name:\"$(name)\"") == 1) || error("Schema $(name) does not exist, use create_schema instead")

    CordraResponse(HTTP.put(uri, auth(cc), JSON.json(obj_json), require_ssl_verification=cc.verify, status_exception=false))

    return true
end

"""
    get_schema(
        cc::CordraConnection,
        schema::AbstractString
    )::Dict{String, Any}

Retrieve schema definition in Cordra by name.

"""
function get_schema(
    cc::CordraConnection,
    schema::AbstractString
)::Dict{String,Any}
    uri = URI(parse(URI, "$(cc.host)/schemas/$(schema)"))
    return _json(CordraResponse(HTTP.get(uri, auth(cc); require_ssl_verification=cc.verify, status_exception=false)))
end


"""
    get_object(
        cc::CodraConnection,
        handle::AbstractString
    )::CordraObject

Retrieve a Cordra object by its unique identifier. Return a `CordraObject`.

"""
function get_object(
    handle::CordraHandle
) 
    cc, hdl = handle.connection, handle.value
    params = Dict{String,Any}("full" => true)
    uri = URI(parse(URI, "$(cc.host)/objects/$hdl"), query=params)
    response = CordraResponse(HTTP.get(uri, auth(cc); require_ssl_verification=cc.verify, status_exception=false))
    return CordraObject(response, cc)
end

"""
    read_payload_info(
        handle::CordraHandle
    )::Vector{Dict{String,Any}}
    read_payload_info(
        co::CordraObject
    )::Vector{Dict{String,Any}}

Retrieve a Cordra object payload info by identifier.
"""
function read_payload_info(
    handle::CordraHandle
)::Vector{Dict{String,Any}}
    # Getting CordraConnection and handle
    cc, hdl = handle.connection, handle.value
    uri = URI(parse(URI, "$(cc.host)/objects/$hdl"), query=Dict{String,Any}("full" => true))
    r = _json(CordraResponse(HTTP.get(uri, auth(cc); require_ssl_verification=cc.verify, status_exception=false)))
    return get(r, "payloads", Vector{Dict{String,Any}}())
end
read_payload_info(co::CordraObject) = read_payload_info(co.handle)

"""
    read_payload(
        co::CordraHandle|CordraObject,
        payload::AbstractString
    )

Retrieve a Cordra object payload by identifier and payload name.
"""
function read_payload(
    handle::CordraHandle,
    payload::AbstractString
)::Vector{UInt8}
    cc, hdl = handle.connection, handle.value
    uri = URI(parse(URI, "$(cc.host)/objects/$hdl"), query=Dict{String,Any}("payload" => payload))
    return CordraResponse(HTTP.get(uri, auth(cc); require_ssl_verification=cc.verify, status_exception=false)).body
end
function read_payload(
    co::CordraObject,
    payload::AbstractString
)
    @assert "payloads" in keys(co.response) "The specified CordraObject has no payloads"
    read_payload(co.handle, payload)
end

"""
    export_payload(
        handle::CordraHandle|CordraObject,
        payload::AbstractString,
        filename::AbstractString
    )

Write the payload out to a file.  Return the filename.
"""
function export_payload(
    handle::CordraHandle,
    payload::AbstractString,
    filename::AbstractString
) 
    open(filename, "w") do f
        write(f, read_payload(handle, payload))
    end
    return filename
end
export_payload(
    co::CordraObject,
    payload::AbstractString,
    filename::AbstractString
)  = export_payload(co.handle, payload, filename)


"""
    update_object(
        co::CordraObject;
        obj_json=nothing,
        jsonPointer=nothing,
        obj_type=nothing,
        dryRun=false,
        payloads::Union{Nothing,CordraPayload,Vector{CordraPayload}}=nothing,
        payloadToDelete=nothing
    )::CordraObject

Update a Cordra object. Return the `CordraObject`.

See the [`create_object`](@ref) documentation for details on `payloads`
"""
function update_object(
    co::CordraObject;
    obj_json=nothing,
    jsonPointer=nothing,
    obj_type=nothing,
    dryRun=false,
    payloads::Union{Nothing,CordraPayload,Vector{CordraPayload}}=nothing,
    payloadToDelete=nothing
)::CordraObject
    # Getting CordraConnection and handle
    cc, handle = _ch(co)

    # Interpreting payload
    _mp(y) = HTTP.Multipart(y...)
    _mp(y::HTTP.Multipart) = y
    # Configure params
    params = Dict{String,Any}("full" => true)
    (isnothing(obj_type)) || (params["type"] = obj_type)
    dryRun && (params["dryRun"] = true)
    (isnothing(jsonPointer)) || (params["jsonPointer"] = jsonPointer)
    isnothing(obj_json) && (data = Dict{String,Any}("content" => JSON.json(co.response["content"])))

    (isnothing(payloadToDelete)) || (params["payloadToDelete"] = payloadToDelete)

    uri = URI(parse(URI, "$(cc.host)/objects/$handle"), query=params)
    ios, pls = _tomultipart(payloads)
    try
        if isempty(pls) # multi-part request
            (isnothing(jsonPointer)) || error("Cannot specify jsonPointer and payloads")
            # Construct the body
            merge!(data, pls)
            body = HTTP.Form(data)
            response = CordraResponse(HTTP.put(uri, auth(cc), body; require_ssl_verification=cc.verify, status_exception=false))
        else # just update object
            isnothing(obj_json) && error("obj_json is required")
            response = CordraResponse(HTTP.put(uri, auth(cc), JSON.json(obj_json); require_ssl_verification=cc.verify, status_exception=false))
        end
        return CordraObject(response, cc)
    catch
        close.(ios)
    end
end

"""
    build_acls(cc::CordraConnection;
        readers::Vector{<:AbstractString} = String[],
        writers::Vector{<:AbstractString} = String[],
        payloadreaders::Vector{<:AbstractString} = String[]
    )::Dict{String,String[]}

Build an access control list from the user names specified in `readers`, `writers` and `payloadreaders`.
The function queries the Cordra instance for User(s) or Group(s) with the specified names
and fills the resulting dictionary with the associated IDs.
"""
function build_acls(cc::CordraConnection;
    readers::Vector{<:AbstractString} = String[],
    writers::Vector{<:AbstractString} = String[],
    payloadreaders::Vector{<:AbstractString} = String[]
)
    get_user_ids(usernames) = mapreduce(append!, usernames, init=String[]) do username
        ids = query_ids(cc,"(type:User AND username=$username) OR (type:Group AND groupName=$username)")
        isempty(ids) && @warn "There was no User/Group associated with the name \"$username\""
        map(id->id.value, ids)
    end
    return Dict(
        "readers" => get_user_ids(readers),
        "writers" => get_user_ids(writers),
        "payloadreaders" => get_user_ids(payloadreaders)
    )
end

"""
    update_acls(
        co::CordraObject,
        acls::Dict{String,Vector{<:AbstractString}};
        dryRun=false
    )::CordraObject
    
Replaces a Cordra object's acls. Return the updated `CordraObject`.
"""
function update_acls(
    co::CordraObject,
    acls::Dict{String, Vector{<:AbstractString}};
    dryRun=false
)::CordraObject
    # Getting CordraConnection and handle
    cc, hdl = co.handle.connection, co.handle.value
    data = Dict{String,Any}(
        "content" => JSON.json(co.response["content"]),
        "acl" => acls
    )
    body = HTTP.Form(data)
    # Configure params
    params = Dict{String,Any}("full" => true)
    dryRun && (params["dryRun"] = true)
    uri = URI(parse(URI, "$(cc.host)/objects/$hdl"), query=params)
    response = CordraResponse(HTTP.put(uri, auth(cc), body; require_ssl_verification=cc.verify, status_exception=false))
    return CordraObject(response, cc)
end

"""
    delete_object(
        cc::CordraConnection,
        handle::AbstractString;   # The object's ID
        jsonPointer=nothing
        )::Bool
    delete_object(
        co::CordraObject;
        jsonPointer::Union{Nothing,AbstractString}=nothing
        )::Bool
    delete_object(
        handle::CordraHandle
    )
If `jsonPointer` is specified, instead of deleting the object, only the content at the specified JSON pointer will be deleted (including the pointer itself).

Delete a Cordra Object. Return `true` if successful.
"""
function delete_object(handle::CordraHandle; params=Dict{String,Any}())
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
function delete_object(
    co::CordraObject;
    jsonPointer::Union{Nothing,AbstractString}=nothing
)::Bool
    params = Dict{String,Any}()
    if !isnothing(jsonPointer)
        @assert strip(jsonPointer, '/') in keys(co.response["content"]) "Invalid jsonPointer"
        params["jsonPointer"] = jsonPointer
    end
    delete_object(co.handle, params=params)
end

"""
    function delete_payload(
        handle::CordraHandle,
        payload::AbstractString
    )::Bool
    delete_payload(
        co::CordraObject,
        payload::AbstractString              # The name of the payload to delete
    )::Bool
    delete_payload(
        cc::CordraConnection,
        handle::AbstractString,              # The object's ID
        payload::AbstractString              # The name of the payload to delete
    )::Bool

Delete a payload from a Cordra object. Return `true` if successful.
"""
function delete_payload(
    handle::CordraHandle,
    payload::AbstractString
)::Bool 
    cc = handle.connection
    params = Dict{String,Any}()
    params["payload"] = payload
    uri = URI(parse(URI, "$(cc.host)/objects/$(handle.value)"), query=params)
    r = _json(CordraResponse(HTTP.delete(uri, auth(cc); require_ssl_verification=cc.verify, status_exception=false)))
    isempty(r) || error("There was an error deleting payload $payload from $handle")
    return true
end
delete_payload(
    co::CordraObject,
    payload::AbstractString
)::Bool = delete_payload(co.handle, payload)
delete_payload(
    cc::CordraConnection,
    handle::AbstractString,
    payload::AbstractString
)::Bool = delete_payload(CordraHandle(handle, cc), payload)

"""
    query(
        cc::CordraConnection,
        query::AbstractString;
        jsonFilter=nothing,   # An optional filter to items in the object
        pageNum::Int=0,       # The desired results page number. 0 is the first page
        pageSize::Int=10
        )::Vector{CordraObject}

Find a Cordra object by query. Return a vector of CordraObject

`pageSize` defines the number of results per page. If negative: no limit.

The syntax for queries is described [here](https://www.cordra.org/documentation/api/search.html) and, 
in more detail, [here](https://lucene.apache.org/core/2_9_4/queryparsersyntax.html).

Examples:

    query(cc, "/Name:Zippy") # Find an object containing a JSON leaf named "Name" with value "Zippy"
    query(cc, "/Name:Zip*") # Wild card matches "Zippy", "Zipper", "Zipzan" etc.
    query(cc, "/x1:[0.0 TO 0.2]") # Find an object with a numeric value named "x1" between 0.0 and 0.2
    query(cc, "(/Name:Zip* OR /Name:Reg*) AND /x1:[0.0 TO 0.8]") # Boolean operators and grouping with (...)
"""
function query( # search using /search POST? look at docs separate search fct
    cc::CordraConnection,
    query::AbstractString;
    sortFields=nothing,
    jsonFilter=nothing,
    pageNum::Int=0,
    pageSize::Int=10
)::Vector{CordraObject}
    (pageSize == 0) && error("Invalid pageSize, use nquery instead.")
    params = Dict{String,Any}(
        "query" => query,
        "full" => true,
        "pageNum" => pageNum,
        "pageSize" => pageSize
    )
    (isnothing(jsonFilter)) || (params["filter"] = string(jsonFilter))
    (isnothing(sortFields)) || (params["sortFields"] = string(sortFields))
    uri = URI(parse(URI, "$(cc.host)/objects/"), query=params)
    response = _json(CordraResponse(HTTP.get(uri, auth(cc); require_ssl_verification=cc.verify, status_exception=false))) #not working well
    return [CordraObject(x, x["id"], cc) for x in response["results"]]
end

"""
    query_ids(
        cc::CordraConnection,
        query::AbstractString;
        pageNum::Int=0,       # The desired results page number. 0 is the first page
        pageSize::Int=10
        )::Vector{CordraHandle}

Find a Cordra object ID by query. Return a vector of CordraHandle

`pageSize` defines the number of results per page. If negative: no limit.

See: query(...) for search string documentation
"""
function query_ids(
    cc::CordraConnection,
    query::AbstractString;
    pageNum::Int=0,
    pageSize::Int=10
)::Vector{CordraHandle}
    params = Dict{String,Any}(
        "query" => query,
        "ids" => true,
        "full" => true,
        "pageNum" => pageNum,
        "pageSize" => pageSize
    )
    uri = URI(parse(URI, "$(cc.host)/objects/"), query=params)
    response = _json(CordraResponse(HTTP.get(uri, auth(cc); require_ssl_verification=cc.verify, status_exception=false)))
    return [CordraHandle(x, cc) for x in response["results"]]
end

"""
    nquery(
        cc::CordraConnection,
        query::AbstractString;
        )::Int

Return the number of results when executing the query.

See: query(...) for search string documentation
"""
function nquery(
    cc::CordraConnection,
    query::AbstractString
)::Int
    params = Dict{String,Any}(
        "query" => query,
        "pageSize" => 0
    )
    uri = URI(parse(URI, "$(cc.host)/objects/"), query=params)
    return _json(CordraResponse(HTTP.get(uri, auth(cc); require_ssl_verification=cc.verify, status_exception=false)))["size"]
end

"""
    read_token( cc::CordraConnection)

Get the properties ("userId", "active", "username" etc) associated with the current authentication token in `cc`.
"""
function read_token(
    cc::CordraConnection
)
    params = Dict{String,Any}("full" => true)
    auth_json = Dict{String,Any}("token" => cc.token)
    uri = URI(parse(URI, "$(cc.host)/auth/introspect"), query=params)
    return _json(CordraResponse(HTTP.request("POST", uri,
        ["Content-type" => "application/json"], JSON.json(auth_json), require_ssl_verification=cc.verify, status_exception=false)))
end

end

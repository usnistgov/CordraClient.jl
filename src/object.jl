"""
    CordraObject(
        response::Dict{String, Any},
        handle::CordraHandle
    )

Represents a Cordra database object in Julia. 

`CordraObjects` are not constructed directly but rather indirectly through the [`create_object`](@ref),
[`update_object`](@ref) or [`get_object`](@ref) methods.

The methods [`handle`](@ref), `content`, `metadata`, `schema_type`, `acl` access
the internals of `CordraObject.`

See the documentation for [`create_object`](@ref) for examples of use.
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

"Returns the 'CordraHandle' uniquely identifying this 'CordraObject'"
handle(co::CordraObject)::CordraHandle = co.handle

"Returns the data associated with this 'CordraObject'"
content(co::CordraObject) = co.response["content"]

"Returns the metadata associated with this 'CordraObject'"
metadata(co::CordraObject) = co.response["metadata"]

"Returns the schema that defines the data in this 'CordraObject'"
schema_type(co::CordraObject) = co.response["type"]

"Return the access-control list associate with this 'CordraObject'"
function acl(co::CordraObject; resolve=true)
    cc = co.handle.connection
    r = get(co.response, "acl", Dict{String,Vector{String}}())
    if resolve
        ids = Vector{String}(union([id for id in values(r)]...))
        for id in ids
            if !haskey(cc.ids, id)
                c = content(get_object(cc, id))
                cc.ids[id] = get(c, "groupName", get(c, "username", id))
            end
        end
        r = begin
            r2 = Dict{String,Vector{String}}()
            for k in keys(r)
                r2[k] = map(id -> cc.ids[id], r[k])
            end
            r2
        end
    end
    return r
end

 """
    create_object(
        cc::CordraConnection,
        obj_json::Union{AbstractDict, Tables.AbstractRow},   # The object's JSON data or a DataFrame row to convert to JSON.
        schema_type::AbstractString;      # The object's data schema name.
        handle::Union{Nothing, AbstractString} = nothing, # The object's ID including Cordra's prefix <prefix/id>
        suffix::Union{Nothing, AbstractString} = nothing, # The object's ID
        dryRun::Bool = false,                # Don't actually add the item
        payloads::Union{Nothing,CordraPayload, Vector{CordraPayload}}=nothing, # Data to attach to the object
        acls::Union{Nothing, AbstractDict} = nothing  # Access control lists (nothing is reader/writer = current connection username)
    )::CordraObject

Create a Cordra database object. Return a `CordraObject`.

The function [`payload`](@ref) and macro cp"...." are useful for constructing payload objects.

# Example
```julia-repl
julia> cc=CordraConnection("https://localhost:8443","user","password")
CordraConnection(https://localhost:8443/test as admin)
julia> my_dict = Dict{String, Any}(["name" => "Julia", "version" => 1.7])
Dict{String, Any} with 2 entries:
  "name"    => "Julia"
  "version" => 1.7
julia> schema_type = "ProgrammingLanguage" # Cordra Object Type (schema in database)
"ProgrammingLanguage"
julia> acls = Dict("readers"=>["nicholas", "camilo"], "writers"=>["camilo"])
julia> cp1=payload("Desktop\\trialC.svg", "image/svg+xml")
julia> cp2=cp"Desktop\\GSR2020.tsv"
julia> obj = create_object(cc, my_dict, schema_type, acls = acls, payloads=[cp1,cp2])
CordraObject(test/e64d664b335757ab1b0e)
julia> content(obj)
Dict{String, Any} with 3 entries:
  "name"    => "Julia"
  "id"      => "test/e64d664b335757ab1b0e"
  "version" => 1.7
julia> handle(obj)
CordraHandle(test/e64d664b335757ab1b0e)
julia> schema_type(obj)
"ProgrammingLanguage"
julia> metadata(obj)
Dict{String, Any} with 5 entries:
  "createdBy"  => "username"
  "txnId"      => 1656157509093001
  "modifiedBy" => "username"
  "createdOn"  => 1656157509090
  "modifiedOn" => 1656157509090
julia> payloads(obj)
2-element Vector{Dict{String, Any}}:
 Dict("name" => "Payload1", "mediaType" => "image/svg+xml", "filename" => "trailC.svg", "size" => 29443)
 Dict("name" => "Payload2", "mediaType" => "text/tab-separated-values", "filename" => "GSR2020.tsv", "size" => 813962)
 julia> fn=export_payload(obj, "Payload2")
 "C:\\Users\\user\\AppData\\Local\\Temp\\jl_ku6bKo\\GSR2020.tsv"
 julia> df=process_payload(io->CSV.read(io, DataFrame, delim="\\t"), co, "Payload2")
 24×6 DataFrame
 Row │ Z      10 keV       20 keV       30 keV   40 keV       49 keV      
     │ Int64  Float64?     Float64?     Float64  Float64?     Float64?
─────┼────────────────────────────────────────────────────────────────────
   1 │     6        0.069        0.06     0.052        0.054        0.052
...
```
"""
function create_object(
    cc::CordraConnection,
    obj_json::Union{AbstractDict, Tables.AbstractRow},
    schema_type::AbstractString;
    handle::Union{Nothing,AbstractString}=nothing,
    suffix::Union{Nothing,AbstractString}=nothing,
    dryRun::Bool=false,
    payloads::Union{Nothing,CordraPayload,Vector{CordraPayload}}=nothing,
    acls::Union{Nothing,AbstractDict}=nothing
)::CordraObject
    # Implementation
    (isnothing(handle)) || (_prefix(cc, handle))
    # Set up uri with params
    params = Dict{String,Any}(
        "type" => schema_type
    )
    (isnothing(suffix)) || (params["suffix"] = replace(suffix, r"\s" => "_"))
    (isnothing(handle)) || (params["handle"] = replace(handle, r"\s" => "_"))
    dryRun && (params["dryRun"] = true)
    params["full"] = true # do not change
    uri = URI(parse(URI, "$(cc.host)/objects"), query=params)
    racls = if isnothing(acls)  # Default to the current logged on username
        resolve_acls(cc, readers=[cc.username], writers=[cc.username])
    else
        resolve_acls(cc, readers=get(acls, "readers", String[]), writers=get(acls, "writers", String[]))
    end
    # Build the data with acl
    data = Dict{String,Any}(
        "content" => JSON.json(obj_json),
        "acl" => JSON.json(racls)
    )
    # Default to read/write/payload read by this user only
    ios, pls = _tomultipart(payloads)
    try
        merge!(data, pls)
        # Post the object
        response = CordraResponse(HTTP.post(uri, auth(cc), HTTP.Form(data); require_ssl_verification=cc.verify, status_exception=false))
        return CordraObject(response, cc)
    finally
        close.(ios)
    end
end

"""
    get_object(
        handle::{AbstractString, CordraHandle}
    )::CordraObject

Retrieve a Cordra object by its unique handle. Return a `CordraObject`.
"""
get_object(
    cc::CordraConnection,
    handle::AbstractString
) = get_object(CordraHandle(handle, cc))

"""
    update_object(
        co::CordraObject;  # The object to update
        obj_json=nothing,  # nothing => maintain the JSON metadata, otherwise something JSON.json(...) can convert
        jsonPointer::Union{Nothing, AbstractString}=nothing,
        schema_type::Union{Nothing, AbstractString}=nothing, # nothing => maintain schema, otherwise new schema
        dryRun::Bool=false,
        payloads::Union{Nothing,CordraPayload,Vector{CordraPayload}}=nothing,
        payloadToDelete=nothing
    )::CordraObject

Update a Cordra object. Return the `CordraObject`.
After an update, the original `co::CordraObject` will no longer accurately represent the contents of the Cordra server. To ensure 
the local object reflects the server object, the recommended syntax is:
```julia
julia> obj = update_object(obj, obj_json=..., payloads=...)
````
which replaces the old defintion of `obj` with the new one.

See the [`create_object`](@ref) documentation for details on `payloads`
"""
function update_object(
    co::CordraObject;
    obj_json=nothing,
    jsonPointer::Union{Nothing,AbstractString}=nothing,
    schema_type::Union{Nothing,AbstractString}=nothing,
    dryRun::Bool=false,
    payloads::Union{Nothing,CordraPayload,Vector{CordraPayload}}=nothing,
    payloadToDelete=nothing
)::CordraObject
    # Getting CordraConnection and handle
    cc, handle = co.handle.connection, co.handle.value

    _data(::Nothing)::Dict{String,Any} = Dict(["content" => JSON.json(co.response["content"])])
    _data(obj_json)::Dict{String,Any} = Dict(["content" => JSON.json(obj_json)])

    # Configure params
    params = Dict{String,Any}("full" => true)
    (isnothing(schema_type)) || (params["type"] = schema_type)
    dryRun && (params["dryRun"] = true)
    (isnothing(jsonPointer)) || (params["jsonPointer"] = jsonPointer)
    (isnothing(payloadToDelete)) || (params["payloadToDelete"] = payloadToDelete)

    uri = URI(parse(URI, "$(cc.host)/objects/$handle"), query=params)
    ios, pls = _tomultipart(payloads)
    try
        if !(isempty(pls)) # multi-part request
            (isnothing(jsonPointer)) || error("Cannot specify jsonPointer and payloads")
            # Construct the body
            data = _data(obj_json)
            merge!(data, pls)
            body = HTTP.Form(data)
            response = CordraResponse(HTTP.put(uri, auth(cc), body; require_ssl_verification=cc.verify, status_exception=false))
        else # just update object
            (!isnothing(jsonPointer) & isnothing(obj_json)) && (error("obj_json is required"))
            data = _data(obj_json)["content"]
            response = CordraResponse(HTTP.put(uri, auth(cc), data; require_ssl_verification=cc.verify, status_exception=false))
        end
        return CordraObject(response, cc)
    catch
        close.(ios)
        rethrow()
    end
end

"""
    delete_object(
        cc::CordraConnection,
        handle::AbstractString;   # The object's ID
        jsonPointer::Union{Nothing, AbstractString}=nothing
        )::Bool
    delete_object(
        co::CordraObject;
        jsonPointer::Union{Nothing,AbstractString}=nothing
        )::Bool
    delete_object(
        handle::CordraHandle
        )::Bool
If `jsonPointer` is specified, instead of deleting the object, only the content at the specified JSON pointer will be deleted (including the pointer itself).

Delete a Cordra Object. Return `true` if successful.
"""
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
    payloads(
        coh::Union{CordraHandle,CordraObject}
    )::Vector{Dict{String,Any}}

Retrieve information about the payload associated with a Cordra object or handle.
"""
payloads(
    obj::CordraObject
)::Vector{Dict{String,Any}} = #
    get(obj.response, "payloads", Vector{Dict{String,Any}}[])

"""
    payload_names(
        co::Union{CordraHandle,CordraObject}
    )::Vector{String}

Retrieve names of payloads associated with a Cordra object or handle.
"""
payload_names(co::Union{CordraHandle,CordraObject}) = #
    String[x["name"] for x in payloads(co)]

"""
    read_payload(
        coh::Union{CordraHandle,CordraObject},
        payload::AbstractString
    )::Vector{UInt8}

Retrieve a Cordra object payload by identifier.
"""
function read_payload(
    co::CordraObject,
    payload::AbstractString
)
    @assert "payloads" in keys(co.response) "The specified CordraObject has no payloads"
    read_payload(co.handle, payload)
end

"""
    export_payload(
        handle::Union{CordraHandle,CordraObject},
        payload::AbstractString,
        filename::AbstractString
    )

Write a payload out to a file.  Return the name of the file to which it was written.
"""
function export_payload(
    co::CordraObject,
    payload::AbstractString,
    filename::Union{Nothing,AbstractString}=nothing
)
    function payload_to_filename(pl, pls)
        i = findfirst(d -> get(d, "name", "") == pl, pls)
        isnothing(i) ? nothing : pls[i]["filename"]
    end
    fname = payload_to_filename(payload, co.response["payloads"])
    @assert !isnothing(fname) "$co does not contain a payload with name = $payload."
    filename = something(
        filename,
        joinpath(mktempdir(), fname)  # A temporary file in a temporary dir that is cleaned up on process exit
    )
    open(filename, "w") do f
        write(f, read_payload(handle(co), payload))
    end
    return filename
end

"""
    process_payload(
        f::Function,
        co::CordraObject,
        payload::AbstractString
    )

Apply the function `f` to an IOStream `io` created from the specified payload. Return the result
from `f(io)`.

```julia-repl
julia> sp=process_payload(loadspectrum, co, "Payload1")
```
"""
function process_payload(
    f::Function,
    co::CordraObject,
    payload::AbstractString
)
    io = IOBuffer(read_payload(handle(co), payload))
    try
        return f(io)
    finally
        close(io)
    end
end

"""
    delete_payload(
        co::Union{CordraHandle,CordraObject},
        payload::AbstractString              # The name of the payload to delete
    )::Bool

Delete a payload from a Cordra object. Return `true` if successful.
"""
delete_payload(
    co::CordraObject,
    payload::AbstractString
)::Bool = delete_payload(co.handle, payload)

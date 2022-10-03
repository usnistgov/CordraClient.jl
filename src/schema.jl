"""
    create_schema(
        cc::CordraConnection,
        name::AbstractString,      # The schema name.
        obj_json::AbstractDict,    # The schema's JSON data.
    )::Bool
    create_schema(
        cc::CordraConnection,
        name::AbstractString,      # The schema name.
        obj_json::AbstractString,  # The JSON schema's path 
    )::Bool
    create_schema(
        cc::CordraConnection,
        obj_json::AbstractString,  # The JSON schema's path 
    )::Bool

Register a Cordra schema definition. Return `true` if successful.

If `name` is not specified, the file's name will be used.

"""
function create_schema(
    cc::CordraConnection,
    name::AbstractString,
    obj_json::AbstractDict,
)::Bool
    # Preconditions
    @assert (nquery(cc, "type:\"Schema\" AND /name:\"$(name)\"") == 0) "Schema $(name) already exists, use update_schema instead"
    # Implementation
    uri = URI(parse(URI, "$(cc.host)/schemas/$(name)"))
    CordraResponse(HTTP.put(uri, auth(cc), JSON.json(obj_json), require_ssl_verification=cc.verify, status_exception=false))
    return true
end
function create_schema(
    cc::CordraConnection,
    name::AbstractString,
    obj_json::AbstractString,
)::Bool
    ispath(obj_json) || (error("obj_json must be a path"))
    json = JSON.parsefile(obj_json)
    return create_schema(cc, name, json)
end
function create_schema(
    cc::CordraConnection,
    obj_json::AbstractString,
)::Bool
    ispath(obj_json) || (error("obj_json must be a path"))
    json = JSON.parsefile(obj_json)
    name = split(basename(obj_json), '.')[1]
    return create_schema(cc, name, json)
end

"""
    update_schema(
        cc::CordraConnection,
        name::AbstractString,      # The schema name.
        obj_json::AbstractDict,    # The schema's JSON data.
    )::Bool

Update a Cordra schema definition. Return `true` if successful.
"""
function update_schema(
    cc::CordraConnection,
    name::AbstractString,
    obj_json::AbstractDict,
)::Bool
    # Preconditions    
    @assert nquery(cc, "type:\"Schema\" AND /name:\"$(name)\"") == 1 "Schema $(name) does not exist, use create_schema instead"
    # Implementation
    uri = URI(parse(URI, "$(cc.host)/schemas/$(name)"))
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
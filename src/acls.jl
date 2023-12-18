"""
    resolve_acls(cc::CordraConnection; readers=String[], writers=String[])

Build an access control list from the user names specified in `readers` and `writers`.
The function queries the Cordra instance for User(s) or Group(s) with the specified names
and fills the resulting dictionary with the associated IDs.
"""
function resolve_acls(cc::CordraConnection; readers=String[], writers=String[])
    function resolve(username)
        get!(cc.username_to_id, username) do 
            ids = query_ids(cc, "(type:User AND username=$username) ) OR (type:Group AND groupName=$username) )")
            if !isempty(ids)
                cc.id_to_username[ids[1].value] = username
                return ids[1].value
            else
                @warn "There is no User or Group associated with the name \"$username\""
            end
        end
    end
    return Dict{String, Vector{String}}(
        "readers" => filter!(!isnothing, resolve.(readers)),
        "writers" => filter!(!isnothing, resolve.(writers)),
    )
end

"""
    update_acls(
        co::CordraObject;
        readers=String[],
        writers=String[]
        dryRun::Bool=false
    )::CordraObject
    
Replaces a Cordra object's access control list. Returns the `co` with the updated `acls` as reported by Cordra
"""
function update_acls(
    co::CordraObject;
    readers=String[],
    writers=String[],
    dryRun::Bool=false
)::CordraObject
    # Getting CordraConnection and handle
    ch = co.handle
    cc, hdl = ch.connection, ch.value
    new_acls = resolve_acls(ch.connection, readers=readers, writers=writers)
    data = JSON.json(new_acls)
    # Configure params
    params = Dict{String,Any}()
    dryRun && (params["dryRun"] = true)
    updated_acls = _json(HTTP.put(
        URI(parse(URI, "$(cc.host)/put/acls/$hdl"), query=params),
        ["Content-type" => "application/json"],
        HTTP.Form(data),
        require_ssl_verification=cc.verify,
        status_exception=false
    ))
    if !dryRun
        co.response["acl"] = updated_acls
    end
    return co
end

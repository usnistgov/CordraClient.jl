"""
    resolve_acls(
        cc::CordraConnection, 
        acls::Dict{String, <:AbstractVector}
    )::Dict{String,String[]}

Build an access control list from the user names specified in `readers` and `writers`.
The function queries the Cordra instance for User(s) or Group(s) with the specified names
and fills the resulting dictionary with the associated IDs.
"""
function resolve_acls(cc::CordraConnection; readers=String[], writers=String[])
    all = union(readers, writers)
    # Look up each unique name once
    for username in all
        if !haskey(cc.usernames, username)
            ids = query_ids(cc, "(type:User AND username=$username) OR (type:Group AND groupName=$username)")
            isempty(ids) && @warn "There is no User/Group associated with the name \"$username\""
            cc.usernames[username] = isempty(ids) ? username : ids[1].value
        end
    end
    return Dict(
        "readers" => [cc.usernames[user] for user in readers],
        "writers" => [cc.usernames[user] for user in writers]
    )
end

"""
    update_acls(
        co::CordraObject;
        readers=String[],
        writers=String[]
        dryRun::Bool=false
    )::CordraObject
    
Replaces a Cordra object's access control list. Returns the updated `CordraObject`.
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
    racls = resolve_acls(ch.connection, readers=readers, writers=writers)
    data = Dict{String,Any}(
        "content" => JSON.json(co.response["content"]),
        "acl" => JSON.json(racls)
    )
    body = HTTP.Form(data)
    # Configure params
    params = Dict{String,Any}("full" => true)
    dryRun && (params["dryRun"] = true)
    uri = URI(parse(URI, "$(cc.host)/objects/$hdl"), query=params)
    response = CordraResponse(HTTP.put(uri, auth(cc), body; require_ssl_verification=cc.verify, status_exception=false))
    return CordraObject(response, cc)
end

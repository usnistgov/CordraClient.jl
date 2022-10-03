"""
A `CordraConnection` represents a persistent validated link to a Cordra digital object management instance.

    CordraConnection(
        host::AbstractString,
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
julia> cc = CordraConnection("https::/localhost:8443","user","password")
CordraConnection(https://localhost:8443/test as user)
```
Note that in the first example, the `CordraConnection` will only be valid inside the `do` block.
In the second, it is valid until it times out or `close(cc)`

See [`create_object`](@ref) for examples of using a CordraConnection.
"""
struct CordraConnection
    host::String # URL of host
    prefix::String # prefix of repository
    username::Union{String,Nothing} # Username
    token::Union{String,Nothing} # Authentication token
    verify::Bool # Require SSL verification?
    usernames::Dict{String,String} # Maps username => id for use in acls
    ids::Dict{String,String} # Maps id => username for use in acls

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
        new(host, _prefix, r["username"], r["access_token"], verify, Dict{String,String}(), Dict{String,String}())
    end
    function CordraConnection(host::AbstractString; verify::Bool=true, full::Bool=false)
        # getting prefix
        p = _json(CordraResponse(HTTP.request(
            "GET",
            "$host/design",
            [],
            [],
            require_ssl_verification=verify,
            status_exception=true
        )))
        _prefix = p["handleMintingConfig"]["prefix"]
        new(host, _prefix, nothing, nothing, verify, Dict{String,String}(), Dict{String,String}())
    end
end

function Base.show(io::IO, cc::CordraConnection) #
    (isnothing(cc.token)) && (print(io, "Unauthenticated CordraConnection($(cc.host)/$(cc.prefix))"); return)
    print(io, "CordraConnection($(cc.host)/$(cc.prefix) as $(cc.username))")
end

"""
    Base.open(f::Function, ::Type{CordraConnection}, host::AbstractString, username::AbstractString, password::Union{Nothing,AbstractString}=nothing; verify::Bool=true, full::Bool=false)
    Base.open(f::Function, ::Type{CordraConnection}, file="config.json"; verify::Bool=true, full::Bool=false)
    
Open a `CordraConnection`, perform the actions detailed in the function `f` on the connection, close the connection and return the output from `f`.
"""
function Base.open(f::Function, ::Type{CordraConnection}, host::AbstractString, username::AbstractString, password::Union{Nothing,AbstractString}=nothing; verify::Bool=true, full::Bool=false)
    cc = CordraConnection(host, username, password; verify=verify, full=full)
    res = missing
    try
        res=f(cc)
    catch
        rethrow()
    finally
        close(cc)
    end
    return res
end


"""
    Base.open(::Type{CordraConnection}, file::AbstractString="config.json"; verify::Bool=true, full::Bool=false)::CordraConnection
    Base.open(::Type{CordraConnection}, host::AbstractString, username::AbstractString, password::Union{Nothing,AbstractString}=nothing; verify::Bool=true, full::Bool=false)::CordraConnection

Opens and returns a connection to a Cordra instance as a `CordraConnection`.
"""
function Base.open(::Type{CordraConnection}, file::AbstractString="config.json"; verify::Bool=true, full::Bool=false)::CordraConnection
    config = JSON.parsefile(file)
    open(CordraConnection, config["host"], config["username"], config["password"], verify=verify, full=full)
end
function Base.open(::Type{CordraConnection}, host::AbstractString, username::AbstractString, password::Union{Nothing,AbstractString}=nothing; verify::Bool=true, full::Bool=false)::CordraConnection
    CordraConnection(host, username, password, verify=verify, full=full)
end


"""
    Base.close(cc::CordraConnection)

Closes the persistent link to a Cordra instance.  The `CordraConnection` instance can no longer be
used to access the instance.
"""
function Base.close(cc::CordraConnection)
    response = HTTP.request(
        "POST",
        "$(cc.host)/auth/revoke",
        ["Content-type" => "application/json"],
        JSON.json(Dict{String,Any}("token" => cc.token)),
        require_ssl_verification=cc.verify,
        status_exception=false
    )
    (response.status != 200) && error(_json(response)) # not successful = no CordraObject
    return true
end

auth(cc::CordraConnection) = #
    !isnothing(cc.token) ? ["Authorization" => "Bearer $(cc.token)"] : []

# Helper to check a handle's prefix against a CordraConnection's prefix
function _prefix(cc::CordraConnection, handle::AbstractString)
    prefix = split(handle, '/')[1]
    @assert prefix == cc.prefix || (startswith(prefix, "\"") && prefix[2:end] == cc.prefix) "Handle's prefix does not match connection's prefix"
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

delete_payload(
    cc::CordraConnection,
    handle::AbstractString,
    payload::AbstractString
)::Bool = delete_payload(CordraHandle(handle, cc), payload)

delete_object(
    cc::CordraConnection,
    handle::AbstractString;
    jsonPointer::Union{Nothing,AbstractString}=nothing
)::Bool = delete_object(get_object(cc, handle); jsonPointer=jsonPointer)

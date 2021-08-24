using HTTP
using URIs
using JSON
using Base64

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
            status_exception = true #question
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



open(CordraConnection, "config.json", verify = false) do cc
    try
        HTTP.put(URI(parse(URI, "$(cc.host)/schemas/debug")), auth(cc), JSON.json(Dict{String, String}([])); require_ssl_verification = false, status_exception = false, verbose = 2)
    catch
        println("Could not upload debug type to $(cc.host)")
    end
end
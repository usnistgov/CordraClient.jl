using HTTP
using URIs
using JSON
using Base64

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

host = ARGS[1]

uri = URI(host * "/schemas/debug")
headers = set_headers(ARGS[2], ARGS[3], nothing)

try
    HTTP.put(uri, headers, JSON.json(Dict([])); require_ssl_verification = false, status_exception = false, verbose = 2)
catch
    println("Could not upload debug type")
end

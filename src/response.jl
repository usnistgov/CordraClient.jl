
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


# Helper to convert UInt8[] to JSON
_json(r::CordraResponse) = JSON.parse(String(copy(r.body)))
_json(r::Vector{UInt8}) = JSON.parse(String(copy(r)))
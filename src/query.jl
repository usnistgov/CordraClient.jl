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
in more detail, [here](https://lucene.apache.org/core/2_9_4/queryparsersyntax.html).  The Lucene
query language has been extended to handle numbers in an ordered manner (see examples.)

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

"""
`CordraClient.jl` is a Julia-language client for interacting with a 
[Cordra](https://cordra.org) digital content management system via 
a HTTP REST interface.

Cordra stores digital data in semi-structured format defined by
the JSON schema representation language.   Data is uploaded in
JSON format.  Large free-form data items can be attached to a 
digital object through payloads.

Queries can be implemented using the 
[Lucene query syntax](https://lucene.apache.org/core/2_9_4/queryparsersyntax.html)
to search through the JSON data.  The matching data objects can
be extracted from the Cordra database along with their payloads.

# Example:
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
julia> objs = query(cc, "/name:Jul*") # Find CordraObject(s) containing a JSON leaf named "name" with value starting with "jul"
```
"""
module CordraClient

using HTTP
using JSON
using URIs
using Tables

# The external interface to the CordraClient package
include("connection.jl")
export CordraConnection
export read_token
include("handle.jl")
include("schema.jl")
export create_schema
export get_schema
export update_schema
export get_schema
include("response.jl")
include("payload.jl")
export CordraPayload
export payload
include("object.jl")
export CordraObject
export create_object
export get_object
export update_object
export delete_object
export content
export handle
export metadata
export schema_type
export payloads
export payload_names
export read_payload
export export_payload
export process_payload
export delete_payload
export @cp_str
include("acls.jl")
export acl
export update_acls
include("query.jl")
export query
export query_ids
export nquery

end

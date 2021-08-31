using CordraClient
using Test
using HTTP
using JSON

@testset "CordraClient.jl" begin

    type = "debug"

    test_object = Dict(
        "String" => "This is a String",
        "Number" => 2.093482,
        "Integer" => 55
    )
  
    my_acls = Dict(
        "writers" => ["public"],
        "readers" => ["public"]
    )

    test_name = "test/testing"
    multiple_ids = map(x -> "test/multiple"*x, string.(1:9))
    path = joinpath(@__DIR__)

    open(CordraConnection, joinpath(path, "config.json"), verify = false) do cc
        if find_object(cc, "id:\"$test_name\"")["size"]==1
            delete_object(cc, test_name)
            @assert find_object(cc, "id:\"$test_name\"")["size"]==0
        end
        if find_object(cc, "/debug")["size"]==0
            update_object(cc, "/schemas/debug", obj_json = Dict{String,Any}())
        end
        @test create_object(cc, test_name, test_object, type, dryRun = true)["Integer"] == 55
        @test create_object(cc, test_name, test_object, type, full = true, dryRun = true)["content"] == test_object
        @test create_object(cc, test_name, test_object, type, acls = my_acls, dryRun = true)["content"] == test_object
        @test find_object(cc, "id:\"$test_name\"")["size"]==0
        @test create_object(cc, test_name, test_object, type, dryRun = true, payloads = ["TextFile" => [ "sample_file.txt", open(joinpath(path, "resources", "sample.txt"))]])["Integer"] == 55
        @test find_object(cc, "id:\"$test_name\"")["size"]==0
        @test create_object(cc, test_name, test_object, type, acls = my_acls, payloads = ["TextFile" => [ "sample_file.txt", open(joinpath(path, "resources", "sample.txt"))]])["id"] == "test/testing"
        @test find_object(cc, "id:\"$test_name\"")["size"]==1
        @test update_object(cc, test_name, obj_json = Dict(["testing" => "update"]), dryRun = true) == Dict(["testing" => "update"])
        @test JSON.parse(String(copy(read_object(cc, test_name)))) == test_object
        @test String(read_object(cc, test_name, jsonPointer ="/Number")) == "2.093482"
        @test read_payload_info(cc, test_name)[1]["size"] in (65,  66) # *NIX vs Windows
        @test String(read_payload(cc, test_name, "TextFile")) in ("This is a sample file to be uploaded as a payload.\r\nJust a sample.", "This is a sample file to be uploaded as a payload.\nJust a sample.") # *NIX vs Windows
        @test update_object(cc, test_name, acls=my_acls, payloads = ["TestingNewFile" => ["alien.png", open(joinpath(path, "resources", "alien.png"))]])["content"]["Integer"] == 55
        @test length(read_payload(cc, test_name, "TestingNewFile")) == 15647
        @test update_object(cc, test_name, jsonPointer = "/Integer", obj_json = 326)["Integer"] == 326
        @test String(read_object(cc, test_name, jsonPointer ="/Integer")) == "326"
        update_object(cc, test_name, payloads = [ "Array" => HTTP.Multipart("Array", IOBuffer(reinterpret(UInt8, collect(1.0:1.0:100.0))), "application/octet-stream")])
        @test length(read_payload_info(cc, test_name)) == 3
        @test isempty(delete_payload(cc, test_name, "TestingNewFile"))
        @test length(read_payload_info(cc, test_name)) == 2
        @test String(read_object(cc, test_name, jsonPointer ="/Number")) == "2.093482"
        for id in multiple_ids
            create_object(cc, id, test_object, type, acls = my_acls)
        end
        @test find_object(cc, "/Number:2.093482")["size"] == 10
        @test length(find_object(cc, "/Number:2.093482", ids = true)["results"]) == 10
        @test Set(find_object(cc, "/Integer:55", ids = true)["results"]) == Set(multiple_ids)
        for id in multiple_ids
            delete_object(cc, id)
        end
        @test find_object(cc, "/Number:2.093482")["size"] == 1
        @test_throws HTTP.ExceptionRequest.StatusError CordraConnection(cc.host, cc.username, "thisisclearlynotyourpassword", verify = false)
        try
            read_object(cc, "notarealid")
        catch e
            @test e.msg == "404 Not Found"        
        end
        @test JSON.parse(String(copy(read_object(cc, test_name, jsonPointer = "Wrong"))))["message"] == "Invalid JSON Pointer Wrong"
        try
            read_object(cc, test_name, jsonPointer = "/Wrong")
        catch e
            @test e.msg == "404 Not Found"   
        end
        try
            read_payload(cc, test_name, "NotARealPayload")
        catch e
            @test e.msg == "404 Not Found"
        end
        try
            delete_payload(cc, test_name, "NotARealPayload")
        catch e
            @test e.msg == "404 Not Found"
        end
        try
            update_object(cc, test_name, jsonPointer = "/String", payloads = Dict("Array" => ("Array",IOBuffer(reinterpret(UInt8, collect(1.0:1.0:100.0))))))
        catch e
            @test e.msg == "Cannot specify jsonPointer and payloads"
        end
        try
            update_object(cc, test_name)
        catch e
            @test e.msg == "obj_json is required"
        end
        try
            delete_object(cc, test_name, jsonPointer = "/WrongPointer")
        catch e
            @test e.msg == "404 Not Found"
        end
        delete_object(cc, test_name, jsonPointer = "/String")
        @test JSON.parse(String(copy(read_object(cc, test_name)))) == Dict(["Number" => 2.093482, "Integer" => 326])
        @test update_object(cc, test_name, acls = [])["message"] == "Invalid ACL format"
        update_object(cc, test_name, acls = Dict(["readers" => [], "writers" => []]))
        @test JSON.parse(String(copy(read_object(cc, test_name, full = true))))["acl"] == Dict(["readers" => [], "writers" => []])
        delete_object(cc, test_name)
        @assert find_object(cc, "id:\"$test_name\"")["size"]==0
        @test_throws MethodError CordraConnection("https://localhost:8443", verify = false)
        @test read_token(cc)["active"] == true
        @test read_token(cc)["username"] == cc.username
        global test_cordra_connection = cc
    end
    try
        read_object(test_cordra_connection, "notarealid")
    catch e
        @test e.msg == "401 Unauthorized"
    end
end

# what did not work:
# open("resources/sample.txt") do io
#     p = ["TextFile" => ["sample_file.txt", io]]
#     @test CordraClient.create_object(host, test_object, type, acls = my_acls, verify = false, token = token, payloads = p, suffix = "testing")["id"] == "test/testing"
# end
using CordraClient
using Test

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
        @test find_object(cc, "id:\"$test_name\"")["size"]==0
        @test create_object(cc, test_name, test_object, type, dryRun = true, payloads = ["TextFile" => [ "sample_file.txt", open(joinpath(path, "resources", "sample.txt"))]])["Integer"] == 55
        @test find_object(cc, "id:\"$test_name\"")["size"]==0
        @test create_object(cc, test_name, test_object, type, acls = my_acls, payloads = ["TextFile" => [ "sample_file.txt", open(joinpath(path, "resources", "sample.txt"))]])["id"] == "test/testing"
        @test find_object(cc, "id:\"$test_name\"")["size"]==1
        @test String(read_object(cc, test_name, jsonPointer ="/Number")) == "2.093482"
        @test read_payload_info(cc, test_name)[1]["size"] in (65,  66) # *NIX vs Windows
        @test String(read_payload(cc, test_name, "TextFile")) in ("This is a sample file to be uploaded as a payload.\r\nJust a sample.", "This is a sample file to be uploaded as a payload.\nJust a sample.") # *NIX vs Windows
        @test update_object(cc, test_name, obj_json = test_object, acls=my_acls, payloads = ["TestingNewFile" => ["alien.png", open(joinpath(path, "resources", "alien.png"))]])["Integer"] == 55
        @test length(read_payload(cc, test_name, "TestingNewFile")) == 15647
        @test update_object(cc, test_name, jsonPointer = "/Integer", obj_json = 326)["Integer"] == 326
        @test String(read_object(cc, test_name, jsonPointer ="/Integer")) == "326"
        update_object(cc, test_name, obj_json=Dict(), payloads = [ "Array" => HTTP.Multipart("Array", IOBuffer(reinterpret(UInt8, collect(1.0:1.0:100.0))), "application/octet-stream")])
        @test length(read_payload_info(cc, test_name)) == 3
        @test update_object(cc, test_name, obj_json = test_object, payloadToDelete = "TestingNewFile") == 55
        @test length(read_payload_info(cc, test_name)) == 2
        delete_object(cc, test_name)
        @assert find_object(cc, "id:\"$test_name\"")["size"]==0
    end
end

# what did not work:
# open("resources/sample.txt") do io
#     p = ["TextFile" => ["sample_file.txt", io]]
#     @test CordraClient.create_object(host, test_object, type, acls = my_acls, verify = false, token = token, payloads = p, suffix = "testing")["id"] == "test/testing"
# end
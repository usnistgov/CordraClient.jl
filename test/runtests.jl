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
    
    open(CordraConnection, "config.json"; verify = false) do cc
        @test create_object(cc, test_object, type, dryRun = true)["Integer"] == 55
        @test create_object(cc, test_object, type, dryRun = true, payloads = ["TextFile" => ["sample_file.txt", open("resources/sample.txt")]])["Integer"] == 55
        @test create_object(cc, test_object, type, acls = my_acls, payloads = ["TextFile" => ["sample_file.txt", open("resources/sample.txt")]], suffix = "testing")["id"] == "test/testing"
        @test read_object(cc, "test/testing", jsonPointer ="/Number") == 2.093482
        @test read_payload_info(cc, "test/testing")[1]["size"] == 65
        @test read_payload(cc, "test/testing", "TextFile") == "This is a sample file to be uploaded as a payload.\nJust a sample."
        @test update_object(cc, "test/testing", obj_json = test_object, acls=my_acls, payloads = p = ["TestingNewFile" => ["sample_file_2.txt", open("resources/sample.txt")]])["Integer"] == 55
        @test read_payload(cc, "test/testing", "TestingNewFile") == "This is a sample file to be uploaded as a payload.\nJust a sample."
        @test update_object(cc, "test/testing", jsonPointer = "/Integer", obj_json = 326) == 326
        @test read_object(cc, "test/testing", jsonPointer ="/Integer") == 326
        @test update_object(cc, "test/testing", obj_json = test_object, payloadToDelete = "TestingNewFile")["Integer"] == 55
        @test length(read_payload_info(cc, "test/testing")) == 1
        @test delete_object(cc, "test/testing") isa Dict
    end
end

"""what did not work:
open("resources/sample.txt") do io
    p = ["TextFile" => ["sample_file.txt", io]]
    @test CordraClient.create_object(host, test_object, type, acls = my_acls, verify = false, token = token, payloads = p, suffix = "testing")["id"] == "test/testing"
end
"""
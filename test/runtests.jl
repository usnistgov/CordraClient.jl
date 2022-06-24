using CordraClient
using Test
using HTTP
using JSON
using DataStructures

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
    test_ord_dict = OrderedDict(
        "First" => "A string",
        "Second" => 1827,
        "Third" => 2.857710001,
        "Fourth" => 29999910
    )

    test_name = "test/testing"
    multiple_ids = map(x -> "test/multiple" * x, string.(1:9))
    path = joinpath(@__DIR__)

    open(CordraConnection, joinpath(path, "config.json"), verify=false) do cc
        if nquery(cc, "id:\"$test_name\"") == 1
            delete_object(cc, test_name)
            @assert nquery(cc, "id:\"$test_name\"") == 0
        end
        if nquery(cc, "/debug") == 0
            create_schema(cc, "debug", Dict{String,Any}())
            # update_object(cc, "/schemas/debug", obj_json = Dict{String,Any}())
        end
        @test create_object(cc, test_object, type, dryRun=true, handle=test_name).response["content"]["Integer"] == 55
        @test create_object(cc, test_object, type, dryRun=true, handle=test_name).response["content"] == test_object
        @test create_object(cc, test_object, type, acls=my_acls, dryRun=true, handle=test_name).response["content"] == test_object
        @test nquery(cc, "id:\"$test_name\"") == 0
        @test create_object(cc, test_object, type, dryRun=true, handle=test_name, payloads=["TextFile" => ["sample_file.txt", open(joinpath(path, "resources", "sample.txt"))]]).response["content"]["Integer"] == 55
        @test nquery(cc, "id:\"$test_name\"") == 0
        ob1 = create_object(cc, test_object, type, acls=my_acls, handle=test_name, payloads=["TextFile" => ["sample_file.txt", open(joinpath(path, "resources", "sample.txt"))]])
        print(ob1, ob1.response["payloads"])
        @test ob1.handle.value == "test/testing"
        @test nquery(cc, "id:\"$test_name\"") == 1
        @test update_object(ob1; obj_json=Dict(["testing" => "update"]), dryRun=true).response["content"] == Dict(["testing" => "update"])
        # @test JSON.parse(String(copy(read_object(cc, test_name)))) == test_object
        # @test String(read_object(cc, test_name, jsonPointer="/Number")) == "2.093482"
        @test read_payload_info(cc, test_name)[1]["size"] in (65, 66) # *NIX vs Windows
        @test String(read_payload(cc, test_name, "TextFile")) in ("This is a sample file to be uploaded as a payload.\r\nJust a sample.", "This is a sample file to be uploaded as a payload.\nJust a sample.") # *NIX vs Windows
        @test update_object(ob1; payloads=["TestingNewFile" => ["alien.png", open(joinpath(path, "resources", "alien.png"))]]).response["content"]["Integer"] == 55
        @test length(read_payload(cc, test_name, "TestingNewFile")) == 15647
        @test update_object(ob1, jsonPointer="/Integer", obj_json=326).response["content"]["Integer"] == 326
        ob1 = update_acls(ob1, Dict(["writers" => [], "readers" => []]))
        @test ob1.response["acl"] == Dict(["writers" => [], "readers" => []])
        @test update_acls(ob1, my_acls; dryRun=true).response["acl"] == my_acls
        ob1 = update_acls(ob1, my_acls)
        @test_throws MethodError update_acls(ob1, Dict(["writers" => "admin", "readers" => ["public"]]))
        # @test String(read_object(cc, test_name, jsonPointer="/Integer")) == "326"
        # res = read_object(cc, test_name, jsonPointer="/Integer")
        # @test (@JSON res) == 326
        # res2 = read_object(cc, test_name)
        # @test (@JSON res2) == Dict("String" => "This is a String", "Number" => 2.093482, "Integer" => 326)
        update_object(ob1, payloads=["Array" => HTTP.Multipart("Array", IOBuffer(reinterpret(UInt8, collect(1.0:1.0:100.0))), "application/octet-stream")])
        @test length(read_payload_info(cc, test_name)) == 3
        @test delete_payload(cc, test_name, "TestingNewFile")
        @test length(read_payload_info(cc, test_name)) == 2
        # @test String(read_object(cc, test_name, jsonPointer="/Number")) == "2.093482"
        @testset "OrderedDict" begin
            if nquery(cc, "id:\"test/ordered\"") == 1
                delete_object(cc, "test/ordered")
                @assert nquery(cc, "id:\"test/ordered\"") == 0
            end
            @test create_object(cc, test_ord_dict, type, dryRun=true, suffix="ordered").response["content"]["Fourth"] == 29999910
            @test create_object(cc, test_ord_dict, type, dryRun=true, suffix="ordered").response["content"] == test_ord_dict
            @test create_object(cc, test_ord_dict, type, acls=my_acls, dryRun=true, suffix="ordered").response["content"] == test_ord_dict
            @test nquery(cc, "id:\"test/ordered\"") == 0
            @test create_object(cc, test_ord_dict, type, dryRun=true, suffix="ordered", payloads=["TextFile" => ["sample_file.txt", open(joinpath(path, "resources", "sample.txt"))]]).response["content"]["Third"] == 2.857710001
            @test nquery(cc, "id:\"test/ordered\"") == 0
            @test create_object(cc, test_ord_dict, type, acls=my_acls, suffix="ordered", payloads=["TextFile" => ["sample_file.txt", open(joinpath(path, "resources", "sample.txt"))]]).handle.value == "test/ordered"
            @test nquery(cc, "id:\"test/ordered\"") == 1
            delete_object(cc, "test/ordered")
            @assert nquery(cc, "id:\"test/ordered\"") == 0
        end

        # TODO create test for DataFrameRow
        # Create test users
        for id in ["test/testuser", "test/testuser2"]
            if nquery(cc, "id:$id") == 1
                delete_object(cc, id)
                @assert nquery(cc, "id:\"$id\"") == 0
            end
        end
        create_object(cc, Dict(["username" => "testuser", "password" => "thisisatestpassword"]), "User", suffix="testuser")
        test_cc = CordraConnection(cc.host, "testuser", "thisisatestpassword", verify=cc.verify)
        try
            create_object(test_cc, Dict(["username" => "testuser2", "password" => "thisisatestpassword"]), "User", suffix="testuser2")
        catch e
            @test occursin("403 Forbidden", e.msg)
        end
        create_object(cc, Dict(["username" => "testuser2", "password" => "thisisatestpassword"]), "User", suffix="testuser2")
        test_cc_2 = CordraConnection(cc.host, "testuser2", "thisisatestpassword", verify=cc.verify)
        # @test JSON.parse(String(copy(read_object(cc, test_name))))["acl"] == my_acls
        update_acls(cc, test_name, Dict(["readers" => [], "writers" => []]))
        try
            get_object(test_cc, test_name)
        catch e
            @test occursin("403 Forbidden", e.msg)
        end
        try
            get_object(test_cc_2, test_name)
        catch e
            @test occursin("403 Forbidden", e.msg)
        end
        # @test String(copy(read_object(cc, test_name, jsonPointer="/Number"))) == "2.093482"
        update_acls(ob1, Dict(["readers" => ["test/testuser"], "writers" => []]))
        # @test String(copy(read_object(test_cc, test_name, jsonPointer="/Number"))) == "2.093482"
        try
            get_object(test_cc_2, test_name)
        catch e
            @test occursin("403 Forbidden", e.msg)
        end
        try
            update_acls(test_cc, test_name, Dict(["readers" => ["test/testuser"], "writers" => ["test/testuser"]]))
        catch e
            @test occursin("403 Forbidden", e.msg)
        end
        update_acls(cc, test_name, Dict(["readers" => ["test/testuser"], "writers" => ["test/testuser2"]]))
        # @test String(copy(read_object(test_cc_2, test_name, jsonPointer="/Number"))) == "2.093482"
        update_acls(test_cc_2, test_name, Dict(["readers" => [], "writers" => []]))
        try
            get_object(test_cc, test_name)
        catch e
            @test occursin("403 Forbidden", e.msg)
        end
        try
            get_object(test_cc_2, test_name)
        catch e
            @test occursin("403 Forbidden", e.msg)
        end
        for id in ["test/testuser", "test/testuser2"]
            delete_object(cc, id)
        end
        for id in ["test/testuser", "test/testuser2"]
            @test nquery(cc, "id:$id") == 0
        end
        for id in multiple_ids
            create_object(cc, test_object, type, acls=my_acls, handle=id)
        end
        @test nquery(cc, "/Number:2.093482") == 10
        @test length(query_ids(cc, "/Number:2.093482")) == 10
        @test Set([x.value for x in query_ids(cc, "/Integer:55")]) == union(Set(multiple_ids), [test_name])
        for id in multiple_ids
            delete_object(cc, id)
        end
        @test nquery(cc, "/Number:2.093482") == 1
        @test_throws HTTP.ExceptionRequest.StatusError CordraConnection(cc.host, cc.username, "thisisclearlynotyourpassword", verify=false)
        try
            get_object(cc, "test/notarealid")
        catch e
            @test occursin("404 Not Found", e.msg)
        end
        @test_throws AssertionError get_object(cc, "notarealid")
        # @test JSON.parse(String(copy(read_object(cc, test_name, jsonPointer="Wrong"))))["message"] == "Invalid JSON Pointer Wrong"
        try
            update_object(cc, test_name, jsonPointer="/Wrong")
        catch e
            @test e.msg == "obj_json is required"
        end
        try
            read_payload(cc, test_name, "NotARealPayload")
        catch e
            @test occursin("404 Not Found", e.msg)
        end
        try
            delete_payload(cc, test_name, "NotARealPayload")
        catch e
            @test occursin("404 Not Found", e.msg)
        end
        try
            update_object(cc, test_name, jsonPointer="/String", payloads=Dict("Array" => ("Array", IOBuffer(reinterpret(UInt8, collect(1.0:1.0:100.0))))))
        catch e
            @test e.msg == "Cannot specify jsonPointer and payloads"
        end
        try
            update_object(cc, test_name)
        catch e
            @test e.msg == "obj_json is required"
        end
        try
            delete_object(cc, test_name, jsonPointer="/WrongPointer")
        catch e
            @test e.msg == "Invalid jsonPointer"
        end
        # @test delete_object(cc, test_name, jsonPointer="/String")
        # @test get_object(cc, test_name).response["content"] == Dict(["Number" => 2.093482, "Integer" => 326])
        # @test JSON.parse(String(copy(read_object(cc, test_name)))) == Dict(["Number" => 2.093482, "Integer" => 326])
        # @test update_object(cc, test_name, acls=[])["message"] == "Invalid ACL format"
        update_acls(cc, test_name, Dict(["readers" => [], "writers" => []]))
        # @test JSON.parse(String(copy(read_object(cc, test_name))))["acl"] == Dict(["readers" => [], "writers" => []])
        delete_object(cc, test_name)
        @assert nquery(cc, "id:\"$test_name\"") == 0
        @test_throws MethodError CordraConnection("https://localhost:8443", verify=false)
        @test read_token(cc)["active"] == true
        @test read_token(cc)["username"] == cc.username
        global test_cordra_connection = cc
    end
    try
        get_object(test_cordra_connection, "test/notarealid")
    catch e
        @test occursin("401 Unauthorized", e.msg)
    end
end

# what did not work:
# open("resources/sample.txt") do io
#     p = ["TextFile" => ["sample_file.txt", io]]
#     @test CordraClient.create_object(host, test_object, type, acls = my_acls, verify = false, token = token, payloads = p, suffix = "testing")["id"] == "test/testing"
# end

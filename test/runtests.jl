using CordraClient
using Test
using HTTP
using JSON
using DataStructures
using DataFrames

@testset "CordraClient.jl" begin

    type = "debug"

    test_object = Dict(
        "String" => "This is a String",
        "Number" => 2.093482,
        "Integer" => 55
    )

    test_ord_dict = OrderedDict(
        "First" => "A string",
        "Second" => 1827,
        "Third" => 2.857710001,
        "Fourth" => 29999910
    )
    test_data_frame = DataFrame("int" => rand(Int64, 10),
        "string" => repeat(["test"], 10),
        "float" => rand(Float64, 10),
        "long_string" => repeat(["Julia is awesome"], 10),
        "bool" => rand(Bool, 10))


    path = joinpath(@__DIR__)

    open(CordraConnection, joinpath(path, "config.json"), verify=false) do cc
        test_name = "$(cc.prefix)/testing"
        multiple_ids = map(x -> "$(cc.prefix)/multiple$x", 1:9)
        df_ids = map(x -> "$(cc.prefix)/df" * x, string.(1:10))
        if nquery(cc, "id:\"$test_name\"") == 1
            delete_object(cc, test_name)
            @assert nquery(cc, "id:\"$test_name\"") == 0
        end
        if nquery(cc, "/$type") == 0
            create_schema(cc, type, Dict{String,Any}())
        end
        @test content(create_object(cc, test_object, type, dryRun=true, handle=test_name))["Integer"] == 55
        @test content(create_object(cc, test_object, type, dryRun=true, handle=test_name)) == test_object
        my_acls = Dict("writers" => ["public", cc.username ], "readers" => ["public", cc.username ])
        @test content(create_object(cc, test_object, type, acls=my_acls, dryRun=true, handle=test_name)) == test_object
        @test nquery(cc, "id:\"$test_name\"") == 0
        payload1 = payload(joinpath(path, "resources", "sample.txt"))
        @test content(create_object(cc, test_object, type, dryRun=true, handle=test_name, payloads=payload1))["Integer"] == 55
        @test nquery(cc, "id:\"$test_name\"") == 0
        ob1 = create_object(cc, test_object, type, acls=my_acls, handle=test_name, payloads=payload1)
        @test ob1.handle.value == "$(cc.prefix)/testing"
        @test nquery(cc, "id:\"$test_name\"") == 1
        @test content(update_object(ob1; obj_json=Dict("testing" => "update"), dryRun=true)) == Dict("testing" => "update")
        @test content(ob1) == test_object
        @test payloads(ob1)[1]["size"] in (65, 66) # *NIX vs Windows
        @test String(read_payload(ob1, "sample.txt")) in ("This is a sample file to be uploaded as a payload.\r\nJust a sample.", "This is a sample file to be uploaded as a payload.\nJust a sample.") # *NIX vs Windows
        payload2 = payload("A very scary alien", joinpath(path, "resources", "alien.png"))
        @test content(update_object(ob1; payloads=payload2))["Integer"] == 55
        @test length(read_payload(ob1.handle, "A very scary alien")) == 15647
        @test content(update_object(ob1, jsonPointer="/Integer", obj_json=326))["Integer"] == 326
        ob2 = update_acls(ob1, writers = [ cc.username ], readers = [ cc.username ])
        # Curiosly, when an object is write by admin, the ACL is not for the admin user (which is hidden from site)
        @test (cc.username == "admin") || acl(ob2) == Dict("writers" => String[ cc.username ], "readers" => String[ cc.username ])
        # @test acl(update_acls(ob2, readers=my_acls["readers"], writers=my_acls["writers"], dryRun=true)) == my_acls
        ob3 = update_acls(ob2, readers=my_acls["readers"], writers=my_acls["writers"])
        @test_throws AssertionError delete_payload(cc, test_name, "TestingNewFile")

        @testset "OrderedDict" begin
            if nquery(cc, "id:\"$(cc.prefix)/ordered\"") == 1
                delete_object(cc, "$(cc.prefix)/ordered")
                @assert nquery(cc, "id:\"$(cc.prefix)/ordered\"") == 0
            end
            @test content(create_object(cc, test_ord_dict, type, dryRun=true, suffix="ordered"))["Fourth"] == 29999910
            @test content(create_object(cc, test_ord_dict, type, dryRun=true, suffix="ordered")) == test_ord_dict
            @test content(create_object(cc, test_ord_dict, type, acls=my_acls, dryRun=true, suffix="ordered")) == test_ord_dict
            @test nquery(cc, "id:\"$(cc.prefix)/ordered\"") == 0
            @test content(create_object(cc, test_ord_dict, type, dryRun=true, suffix="ordered", payloads=[payload1, payload2]))["Third"] == 2.857710001
            @test nquery(cc, "id:\"$(cc.prefix)/ordered\"") == 0
            @test create_object(cc, test_ord_dict, type, acls=my_acls, suffix="ordered", payloads=payload2).handle.value == "$(cc.prefix)/ordered"
            @test nquery(cc, "id:\"$(cc.prefix)/ordered\"") == 1
            delete_object(cc, "$(cc.prefix)/ordered")
            @assert nquery(cc, "id:\"$(cc.prefix)/ordered\"") == 0
        end

        # TODO create test for DataFrameRow
        # Create test users
        for id in ["$(cc.prefix)/testuser", "$(cc.prefix)/testuser2"]
            if nquery(cc, "id:$id") == 1
                delete_object(cc, id)
                @assert nquery(cc, "id:\"$id\"") == 0
            end
        end
        if cc.username == "admin"
            create_object(cc, Dict("username" => "testuser", "password" => "thisisatestpassword"), "User", suffix="testuser")
            test_cc = CordraConnection(cc.host, "testuser", "thisisatestpassword", verify=cc.verify)
            try
                create_object(test_cc, Dict("username" => "testuser2", "password" => "thisisatestpassword"), "User", suffix="testuser2")
            catch e
                @test startswith(e.msg, "403 Forbidden. Forbidden")
            end
            create_object(cc, Dict("username" => "testuser2", "password" => "thisisatestpassword"), "User", suffix="testuser2")
            test_cc_2 = CordraConnection(cc.host, "testuser2", "thisisatestpassword", verify=cc.verify)
            # @test JSON.parse(String(copy(read_object(cc, test_name))))["acl"] == my_acls
            update_acls(ob1, readers = [], writers = [])
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
            update_acls(ob1, readers = [ "testuser" ], writers = [])
            # @test String(copy(read_object(test_cc, test_name, jsonPointer="/Number"))) == "2.093482"
            try
                get_object(test_cc_2, test_name)
            catch e
                @test occursin("403 Forbidden", e.msg)
            end
            try
                update_acls(ob1, readers = ["testuser"], writers = ["testuser"])
            catch e
                @test occursin("403 Forbidden", e.msg)
            end
            update_acls(ob1, readers = ["testuser"], writers = ["testuser2"])
            # @test String(copy(read_object(test_cc_2, test_name, jsonPointer="/Number"))) == "2.093482"
            update_acls(get_object(test_cc_2, test_name), readers = [], writers = [])
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
            for id in ["$(cc.prefix)/testuser", "$(cc.prefix)/testuser2"]
                delete_object(cc, id)
            end
            for id in ["testuser", "testuser2"]
                @test nquery(cc, "id:$id") == 0
            end
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
            get_object(cc, "$(cc.prefix)/notarealid")
        catch e
            @test occursin("404 Not Found", e.msg)
        end
        @test_throws AssertionError get_object(cc, "notarealid")
        # @test JSON.parse(String(copy(read_object(cc, test_name, jsonPointer="Wrong"))))["message"] == "Invalid JSON Pointer Wrong"
        try
            update_object(ob1; jsonPointer="/Wrong")
        catch e
            @test e.msg == "obj_json is required"
        end
        try
            read_payload(ob1, "NotARealPayload")
        catch e
            @test occursin("404 Not Found", e.msg)
        end
        try
            update_object(ob1; jsonPointer="/String", payloads=payload(joinpath(path, "config.json")))
        catch e
            @test e.msg == "Cannot specify jsonPointer and payloads"
        end
        try
            update_object(ob1; jsonPointer="/String")
        catch e
            @test e.msg == "obj_json is required"
        end
        try
            delete_object(ob1, jsonPointer="/WrongPointer")
        catch e
            @test e.msg == "Invalid jsonPointer"
        end
        # @test delete_object(cc, test_name, jsonPointer="/String")
        # @test content(get_object(cc, test_name)) == Dict("Number" => 2.093482, "Integer" => 326)
        # @test JSON.parse(String(copy(read_object(cc, test_name)))) == Dict("Number" => 2.093482, "Integer" => 326)
        # @test update_object(cc, test_name, acls=[])["message"] == "Invalid ACL format"
        # update_acls(cc, test_name, readers => [], writers => [])
        # @test JSON.parse(String(copy(read_object(cc, test_name))))["acl"] == Dict("readers" => [], "writers" => [])
        delete_object(cc, test_name)
        @assert nquery(cc, "id:\"$test_name\"") == 0
        @test read_token(cc)["active"] == true
        @test read_token(cc)["username"] == cc.username
        global test_cordra_connection = cc
    end
    try
        get_object(test_cordra_connection, "$(test_cordra_connection.prefix)/notarealid")
    catch e
        @test occursin("401 Unauthorized", e.msg)
    end
end

# what did not work:
# open("resources/sample.txt") do io
#     p = ["TextFile" => ["sample_file.txt", io]]
#     @test CordraClient.create_object(host, test_object, type, acls = my_acls, verify = false, token = token, payloads = p, suffix = "testing")["id"] == "$(cc.prefix)/testing"
# end

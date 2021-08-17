using CordraClient
using Test

host, username, password = CordraClient.ReadConfig()

token = CordraClient.CreateToken(host, username, password, verify = false)
type = "debug"

test_object = Dict()
test_object["String"] = "This is a String"
test_object["Number"] = 2.093482
test_object["Integer"] = 55


my_acls = Dict()
my_acls["writers"] = ["public"]
my_acls["readers"] = ["public"]



@testset "CordraClient.jl" begin
    @test CordraClient.CheckConnectionTest(host)
    @test CordraClient.ReadToken(host, token, verify = false)["active"] == true
    @test CordraClient.CreateObject(host, test_object, type, dryRun = true, verify = false, token = token)["Integer"] == 55
    @test CordraClient.CreateObject(host, test_object, type, dryRun = true, verify = false, token = token, payloads = ["TextFile" => ["sample_file.txt", open("resources/sample.txt")]])["Integer"] == 55
    @test CordraClient.CreateObject(host, test_object, type, acls = my_acls, verify = false, token = token, payloads = ["TextFile" => ["sample_file.txt", open("resources/sample.txt")]], suffix = "testing")["id"] == "test/testing"
    @test CordraClient.ReadObject(host, "test/testing", verify = false, token = token, jsonPointer ="/Number") == 2.093482
    @test CordraClient.ReadPayloadInfo(host, "test/testing", verify = false, token = token)[1]["size"] == 65
    @test CordraClient.ReadPayload(host, "test/testing", "TextFile", verify = false, token = token) == "This is a sample file to be uploaded as a payload.\nJust a sample."
    @test CordraClient.UpdateObject(host, "test/testing", obj_json = test_object, acls=my_acls, token = token, verify = false, payloads = p = ["TestingNewFile" => ["sample_file_2.txt", open("resources/sample.txt")]])["Integer"] == 55
    @test CordraClient.ReadPayload(host, "test/testing", "TestingNewFile", verify = false, token = token) == "This is a sample file to be uploaded as a payload.\nJust a sample."
    @test CordraClient.UpdateObject(host, "test/testing", jsonPointer = "/Integer", obj_json = 326, verify = false, token = token) == 326
    @test CordraClient.ReadObject(host, "test/testing", verify = false, token = token, jsonPointer ="/Integer") == 326
    @test CordraClient.UpdateObject(host, "test/testing", obj_json = test_object, verify = false, token = token, payloadToDelete = "TestingNewFile")["Integer"] == 55
    @test length(CordraClient.ReadPayloadInfo(host, "test/testing", verify = false, token = token)) == 1
    @test CordraClient.DeleteObject(host, "test/testing", verify = false, token = token) isa Dict
end

"""what did not work:
open("resources/sample.txt") do io
    p = ["TextFile" => ["sample_file.txt", io]]
    @test CordraClient.CreateObject(host, test_object, type, acls = my_acls, verify = false, token = token, payloads = p, suffix = "testing")["id"] == "test/testing"
end
""""
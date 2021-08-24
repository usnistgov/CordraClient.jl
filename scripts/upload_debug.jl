using CordraClient
using JSON

try
    open(CordraConnection, ARGS[1], ARGS[2], ARGS[3], verify = false) do cc
        if !find_object(cc, "/debug")
            update_object(cc, "/schemas/debug", obj_json = JSON.json(Dict([])))))
        end
    end
catch
    println("Could not upload debug type")
end

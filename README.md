# CordraClient for Julia

A client library for interacting with a server-based instance of the Cordra (https://www.cordra.org/) 
digital object management system using the Julia language.  The Cordra system allows users to associate 
metadata with digital payloads.  The metadata is readily searched using a 
[flexible search syntax](https://www.cordra.org/documentation/api/search.html) that is suitable
for both text and numeric metadata.

Cordra can be used for many different types of digital data - like library card catalogs, music archives,
and document stores.  We use it for [FAIR](https://en.wikipedia.org/wiki/FAIR_data) scientific data.

This client library has been developed by Camilo Velez, a student at Montgomery College, under the
direction of Zach Trautt and Nicholas Ritchie from the National Institute of Standards and Technology.

See the documentation for [`create_object`](@ref) and [`docs/Usage.ipynb`](https://github.com/usnistgov/CordraClient.jl/blob/master/doc/Usage.ipynb) for examples of routine use.
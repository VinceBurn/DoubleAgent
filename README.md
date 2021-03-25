# Double Agent

When the api is not ready, you need a double agent to push your development forward.

# Goals

Easy to confugure, locally run server.

Will be acheive by scripting as much as possible, providing tools to quickly seed data and use docker for local deployment.


# Installation

Currently run it directly from xcode.

*Docker should work, but is not officially supported for now*


# Storage

Request information and reponses are currently stored in memory.

# Possible Workflow
TODO: revisit

* Create and share response mapping files for a dedicated use case
* Seed the server with the files (using the toDoubleAgent tool)
* Make your app request host point to localhost:8080 or http://127.0.0.1:8080
* Enjoy your fake data


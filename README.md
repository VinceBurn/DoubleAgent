# Double Agent

When the api is not ready, you need a double agent to push your development forward.

# Goals

Easy to configure, locally run server.

Will be acheived by scripting as much as possible, providing tools to quickly seed data and use docker for local deployment.

# Installation

## Xcode
You can run the Double Agent from Xcode.

To generate the Xcode project:
* Double click on Package.swift
* or use command `vapor xcode` if you have installed the [Vapor Toolbox](https://docs.vapor.codes/4.0/install/macos/)

## Docker
See [Docker usage README](DoubleAgent/Docker_scripts/README.md).

# Storage

Request information and responses are currently stored in memory.

# Mocking Calls

The mocking server expose an API to manipulate the mock data set. [See API reference](DoubleAgent/README.md).

Use the `toDoubleAgent` command line tool to quickly replace the whole data set. [toDoubleAgent reference](Tools/toDoubleAgent/README.md)

# Possible Workflow
TODO: revisit

* Create and share response mapping files for a dedicated use case
* Seed the server with the files (using the toDoubleAgent tool)
* Make your app request host point to localhost:8080 or http://127.0.0.1:8080
* Enjoy your fake data

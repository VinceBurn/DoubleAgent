# Double Agent

# Mock Server API

The server expose its API at `localhost:8080/mocks`

Function  | Method   | Path
--------  | ------   | ------
Help      | GET      | mocks/help
Create    | POST     | mocks
Get All   | GET      | mocks
Reset All | DELETE   | mocks/resetAll

For more details see (spec.swagger)[./spec.swagger] or (spec-example.json)[./spec-example.json]

## toDoubleAgent

Use the `toDoubleAgent` command line tool to simplify the data seeding.

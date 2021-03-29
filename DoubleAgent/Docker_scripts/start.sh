#! /bin/bash

echo "Will run double agent on port 8080"

pushd .. > /dev/null

docker run --detach --rm -p 8080:8080 --name double_agent double-agent:latest

popd > /dev/null

echo "done"

#! /bin/bash

echo "Will build double-agent:latest"

pushd .. > /dev/null

docker build --no-cache -t double-agent:latest .

popd > /dev/null

echo "done"

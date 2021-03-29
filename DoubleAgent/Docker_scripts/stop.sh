#! /bin/bash

echo "Will stop Double Agent"

pushd .. > /dev/null

docker stop double_agent

popd > /dev/null

echo "done"

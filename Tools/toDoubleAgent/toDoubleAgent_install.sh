#! /bin/bash

echo "Will compile toDoubleAgent product"
swift build -c release --product toDoubleAgent
echo "----------"
echo "Will Copy product to /usr/local/bin/"
cp .build/release/toDoubleAgent /usr/local/bin/toDoubleAgent
echo "Done"


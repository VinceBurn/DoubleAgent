# Docker

This folder contain 3 scripts that document how to build, start and stop a **Double Agent** using Docker.

# build

Build a docker image that will be use by the `start` script.

## House Keeping

If you build multiple time the same image, the old one will still exist (`docker images`).
You will need to manually remove them to free up some disk space (`docker rmi [old image id]`).

# start

Run the Double Agent image that was build by the `build` script in a container named `double_agent`.
Only 1 can run at any given time. Stop it using the `stop` script.

The Double Agent will be reachable at `localhost:8080`

## Note

No container name `double_agent` should exist when this script is invoke, or it will fail.
If you start / stop the Double Agent with the `start` and `stop` script, the agent will be removed on stop.

# stop

Stop the container named `double_agent`.
If the container was started using the `start` script, the container will also be remove.

# Useful Docker Command

* `docker images`
* `docker rmi [images ID]`
* `docker ps -a`
* `docker rm [container name or ID]`

`ID` don't need to be fully specified, the few first character are good.

If you don't know docker, do a small tutorial to learn the basis.

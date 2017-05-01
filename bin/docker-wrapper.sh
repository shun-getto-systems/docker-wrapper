#!/bin/bash

declare -A docker_wrapper_images
declare -a docker_wrapper_image_names

declare -a docker_wrapper_args
declare -a docker_wrapper_envs

declare docker_wrapper_has_tty

declare docker_wrapper_server_name
declare docker_wrapper_server_cmd

docker_wrapper_parse_args(){
  while [ $# -gt 0 ]; do
    case "$1" in
      -*)
        docker_wrapper_arg "$1"
        ;;
      *=*)
        docker_wrapper_env "-e$1"
        ;;
      *)
        docker_wrapper_arg "$1"
        ;;
    esac
    shift
  done
}
docker_wrapper_arg(){
  while [ $# -gt 0 ]; do
    docker_wrapper_args[${#docker_wrapper_args[@]}]=$1; shift
  done
}
docker_wrapper_env(){
  while [ $# -gt 0 ]; do
    docker_wrapper_envs[${#docker_wrapper_envs[@]}]=$1; shift
  done
}

docker_wrapper_home(){
  echo "-eHOME=$HOME" "-v" "dotfiles:$HOME"
}

docker_wrapper_check_tty(){
  if [ -t 1 ]; then
    docker_wrapper_has_tty=1
  fi
}
docker_wrapper_tty(){
  local -a opts

  if [ -n "$docker_wrapper_has_tty" ]; then
    docker_wrapper_opt -it --detach-keys ctrl-@,ctrl-@
  fi

  echo "${opts[@]}"
}

docker_wrapper_volumes(){
  local volume
  local -a opts

  if [ -n "$DOCKER_WRAPPER_VOLUMES" ]; then
    for volume in $DOCKER_WRAPPER_VOLUMES; do
      docker_wrapper_opt -v $volume
    done
  fi

  echo "${opts[@]}"
}

docker_wrapper_map(){
  docker_wrapper_images[$1]=$2
  docker_wrapper_image_names[${#docker_wrapper_image_names[@]}]="$1:$2"
}
docker_wrapper_image(){
  local image
  local tag

  image=$1
  tag=${docker_wrapper_images[$image]}

  if [ -n "$tag" ]; then
    case "$tag" in
      *:*)
        echo $tag
        ;;
      *)
        echo $image:$tag
        ;;
    esac
  else
    >&2 echo "map not found for '$image'"
    if [ -n "${docker_wrapper_image_names}" ]; then
      >&2 echo "image map:"
      for image in ${docker_wrapper_image_names[@]}; do
        >&2 echo "  $image"
      done
    fi
    echo $image:-unknown
  fi
}

docker_wrapper_opt(){
  while [ $# -gt 0 ]; do
    opts[${#opts[@]}]=$1; shift
  done
}

docker_wrapper_server(){
  local service
  local mode

  service=$1; shift
  if [ -z "$service" ]; then
    >&2 echo "usage: docker_wrapper_server <service>"
    return
  fi

  docker_wrapper_server_name=$DOCKER_WRAPPER_SERVER_HOSTNAME-$service

  docker_wrapper_server_env_$service

  mode=${docker_wrapper_args[0]}
  if [ -z "$mode" ]; then
    mode=start
  fi

  case "$mode" in
    start)
      docker_wrapper_server_start
      ;;
    stop)
      docker_wrapper_server_purge
      ;;
    restart)
      docker_wrapper_server_purge
      docker_wrapper_server_start
      ;;
    logs)
      docker_wrapper_server_logs
      ;;
    status)
      docker_wrapper_server_status
      ;;
    ps)
      docker_wrapper_server_ps -a
      ;;
    *)
      echo "unknown option '$mode'"
      echo
      echo "available options:"
      echo "  status : check for running"
      echo "  start : start server if not running"
      echo "  stop : stop server if running"
      echo "  restart : stop and start server"
      echo "  logs : show server logs"
      echo "  status : check for running"
      echo "  ps : show docker ps"
      ;;
  esac
}
docker_wrapper_server_name(){
  echo --name $docker_wrapper_server_name -h $docker_wrapper_server_name
}
docker_wrapper_server_start(){
  if [ -z "$(docker_wrapper_server_is_running -a)" ]; then
    docker_wrapper_server_cmd=start
  else
    docker_wrapper_server_status_container_exists
  fi
}
docker_wrapper_server_purge(){
  if [ -z "$(docker_wrapper_server_is_running -a)" ]; then
    docker_wrapper_server_status_not_running
  else
    echo "stop..."
    docker stop $docker_wrapper_server_name
    echo "rm..."
    docker rm $docker_wrapper_server_name
  fi
}
docker_wrapper_server_logs(){
  if [ -n "$(docker_wrapper_server_is_running -a)" ]; then
    docker logs $docker_wrapper_server_name
  else
    docker_wrapper_server_status_not_running
  fi
}

docker_wrapper_server_status(){
  if [ -z "$(docker_wrapper_server_is_running -a)" ]; then
    docker_wrapper_server_status_not_running
  else
    docker_wrapper_server_status_container_exists
  fi
}
docker_wrapper_server_status_not_running(){
  echo not running.
}
docker_wrapper_server_status_container_exists(){
  if [ -n "$(docker_wrapper_server_is_running)" ]; then
    echo already running.
  else
    echo error exited.
  fi
}

docker_wrapper_server_ps(){
  docker ps -f name=$docker_wrapper_server_name "$@"
}
docker_wrapper_server_is_running(){
  docker_wrapper_server_ps --format "{{.ID}}" "$@"
}


##
# ENTRYPOINT
#

# load map definitions
. docker-wrapper.rc.sh

docker_wrapper_parse_args "$@"
docker_wrapper_check_tty

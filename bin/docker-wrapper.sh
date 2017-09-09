#!/bin/bash

declare -a docker_wrapper_envs

declare docker_wrapper_has_tty

declare docker_wrapper_server_name
declare docker_wrapper_server_cmd

docker_wrapper_env(){
  while [ $# -gt 0 ]; do
    docker_wrapper_envs[${#docker_wrapper_envs[@]}]=$1; shift
  done
}

docker_wrapper_set_env_from_current_env(){
  local ifs_org
  local line
  local env_file

  ifs_org=$IFS
  IFS=$'\n'
  for line in $(env); do
    IFS=$ifs_org
    case "$line" in
      ENV_FILES=*)
        ifs_org=$IFS
        IFS=,
        for env_file in ${line#ENV_FILES=}; do
          IFS=$ifs_org
          docker_wrapper_env --env-file $env_file
        done
        ;;
      *)
        if docker_wrapper_set_env_from_current_env_include $line; then
          docker_wrapper_env "-e$line"
        fi
        ;;
    esac
  done
}
docker_wrapper_set_env_from_current_env_include(){
  local exclude_env

  ifs_org=$IFS
  IFS=,
  for exclude_env in ${DOCKER_WRAPPER_EXCLUDE_ENVS:-PATH,LANG}; do
    IFS=$ifs_org
    case "$line" in
      ${exclude_env}=*)
        return 1
        ;;
    esac
  done
}

docker_wrapper_check_tty(){
  if [ -t 1 ]; then
    docker_wrapper_has_tty=1
  fi
}
docker_wrapper_tty(){
  if [ -n "$docker_wrapper_has_tty" ]; then
    echo "-it --detach-keys ctrl-[,ctrl-["
  fi
}

docker_wrapper_volumes(){
  if [ -n "$DOCKER_WRAPPER_VOLUMES" ]; then
    echo -v ${DOCKER_WRAPPER_VOLUMES//,/ -v }
  fi
}

docker_wrapper_image(){
  local image
  local tag_var_name
  local tag

  image=$1
  tag_var_name=DOCKER_WRAPPER_IMAGE_$image
  tag=${!tag_var_name}

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
    echo $image:-unknown
  fi
}

docker_wrapper_server(){
  local service
  local mode
  local service_opts_name
  local service_opts

  service=$1; shift
  mode=$1; shift

  if [ -z "$service" ]; then
    >&2 echo "usage: docker_wrapper_server <service>"
    return
  fi
  service_opts_name=DOCKER_WRAPPER_SERVER_OPTS_$service
  service_opts=${!service_opts_name}

  docker_wrapper_server_name=$DOCKER_WRAPPER_SERVER_HOSTNAME-$service

  if [ -n "$service_opts" ]; then
    docker_wrapper_env $service_opts
  fi

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

docker_wrapper_check_tty
docker_wrapper_set_env_from_current_env

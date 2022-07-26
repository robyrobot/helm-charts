#!/usr/bin/env bash
VALUES="${1:-${VALUES:?missing values file}}"

[ -e "$VALUES" ] && {
    TMP="$(pwd)/bucardo_tmp"
    mkdir -p $TMP &> /dev/null

    trap "rm -rf $TMP" SIGHUP SIGTERM EXIT

    helm template -s templates/configmap.yaml -f $VALUES . | yq -r '.data."bucardo.sh"' | tee $TMP/bucardo.sh > /dev/null
       
    docker run -it -v "$TMP/bucardo.sh:/media/bucardo/bucardo.sh" ghcr.io/robyrobot/bucardo_docker_image:v5.6.0-nj-3
}
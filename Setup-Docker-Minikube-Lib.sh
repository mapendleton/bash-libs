#!/usr/bin/env bash
# A library of functions that allow starting docker and minikube in any env, 
# including WSL which requires some configuration

CHECK_MARK="\033[0;32m\xE2\x9C\x94\033[0m"
CROSS_MARK="\u274c"

#initialize Setup-Docker-Minikube-Log.txt
> Setup-Docker-Minikube-Log.txt

#######################################
# Print progress dots as command waits to return success code 0
# ARGUMENTS:
#   Command to run
#   String to print
#   Timeout int
# OUTPUTS:
#   dot progress bar followed by checkmark and user specified string on success
# RETURN:
#   0 if succeeds, non-zero on error.
#######################################
function wait_prompt() {
    echo -n "Executing command : '$1'"
    if [[ -z $3 ]]; then
        timeout=100
    fi
    while : ; do
        for i in {1..3}; do 
            echo -n "."
            sleep 0.3
        done
        echo -en "\b\b\b\033[0K"
        sleep 0.5
        ((timeout-=1))
        if $1 2>&1 > Setup-Docker-Minikube-Log.txt; then
            echo -e "\r\033[2K${CHECK_MARK} $2"
            break 
        else
            echo $? >> Setup-Docker-Minikube-Log.txt 2>&1
        fi

        if [[ timeout -le 0 ]]; then 
            echo "timeout of $timeout reached..."
            echo -e "${CROSS_MARK} $2"
            exit 1
        fi
    done
}

#######################################
# Checks what environment script is running on and sets some variables
# GLOBALS:
#   UNAME
#   PATH
#   DOCKER_HOST
# OUTPUTS:
#   variables affected.
# RETURN:
#   0 if succeeds, non-zero on error.
#######################################
function get_env() {
    if grep -iEq "(microsoft|wsl)" /proc/version &> /dev/null; then
        UNAME="wsl"
        export PATH="/mnt/c/minikube:$PATH"
        export DOCKER_HOST="unix:///var/run/docker.sock"
    else
        echo assuming env build for mac...
        UNAME="$(uname -s)"
    fi

    echo "Environment = $UNAME"
    if [[ $UNAME == "wsl" ]]; then
        echo -e "windows minikube added to PATH.\nDOCKER_HOST updated to = $DOCKER_HOST"
    fi
}

#######################################
# Overrides minikube command to work based on environment
# RETURN:
#   0 if succeeds, 1 on error.
#######################################
function __minikube() {
    if ! __check_for_req_vars; then exit 1; fi
    case "$UNAME" in 
        Linux | Darwin)
            minikube $@;;
        wsl)
            minikube.exe $@;;
        *)
            echo 'unhandled env : $UNAME'
            exit 1;;
    esac
}

#######################################
# Will attempt to run minikube and configure kubectl, if it's not running
# Will also start docker/colima if not running
# calls function start_docker() if docker is not running
# GLOBALS:
#   DOCKER_CERT_PATH
#   KUBECONFIG
#   UNAME
# RETURN:
#   0 if succeeds, 1 on error.
#######################################
function start_minikube() {
    if ! __check_for_req_vars; then exit 1; fi
    #check status of minikube
    if ! __minikube status >> Setup-Docker-Minikube-Log.txt 2>&1; then
        echo "Minikube not running..."
        #check status of docker
        if ! docker info >> Setup-Docker-Minikube-Log.txt 2>&1; then
            echo "docker not running...";
            start_docker
        fi
        __minikube start --ports=127.0.0.1:30080:30080
    fi

    eval $(__minikube docker-env --shell bash) >> Setup-Docker-Minikube-Log.txt 2>&1
    if [[ $UNAME == wsl ]]; then 
        #convert windows path to wsl path
        DOCKER_CERT_PATH=$(wslpath -a $DOCKER_CERT_PATH)
        echo -n "configuring kubectl for wsl..."
        export KUBECONFIG=/mnt/c/Users/$USER/.kube/config
        kubeServer=$(kubectl config view --output jsonpath={$.clusters[0].cluster.server})
        export KUBECONFIG=/home/$USER/.kube/config
        kubectl config set-cluster minikube --server=$kubeServer
        echo -e "\r\033[2K${CHECK_MARK} kubectl configured for wsl."
    fi

    wait_prompt "__minikube status" "Minikube Running"
}

#######################################
# Starts docker/colima based on env
# GLOBALS:
#   UNAME
# RETURN:
#   0 if succeeds, 1 on error.
#######################################
function start_docker() {
    if ! __check_for_req_vars; then exit 1; fi
    case "$UNAME" in 
    Darwin)
        colima start;;
    Linux)
        sudo service docker start;;
    wsl)
        /mnt/c/"Program Files"/Docker/Docker/"Docker Desktop".exe &;;
    *)
        echo 'unhandled env : $UNAME'
        exit 1;;
    esac

    wait_prompt "docker info" "Docker Started"
}

#######################################
# Makes sure req vars are populated
# RETURN:
#   0 if succeeds, 1 on error.
#######################################
function __check_for_req_vars() {
    if [[ -z $UNAME ]]; then
        echo "var UNAME must be set. Run function 'get_env()'"
        exit 1
    fi
}
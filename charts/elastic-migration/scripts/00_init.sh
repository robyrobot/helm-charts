# 00_init.sh
#

function info() {
  echo -e "$(date +"%Y-%m-%d %H:%M:%S") => [i] $@"
}

function error() {
  echo -e "$(date +"%Y-%m-%d %H:%M:%S") => [✘] $@"
}

function progress() {
  local w=30 p=$1;
  shift;
  printf -v dots "%*s" "$(( $p*$w/100 ))" "";
  dots=${dots// /#};
  #printf "[%-*s] %3d %% %s" "$w" "$dots" "$p" "$*";  
  printf "[%-*s] %s" "$w" "$dots" "$*";
}

# print huma readable time
secs_to_human() {
    echo "$(( $1 / 3600 ))h $(( ($1 / 60) % 60 ))m $(( $1 % 60 ))s"
}

# check for prerequisites
apt-get update > /dev/null

which curl > /dev/null || {
  info "Install curl" && {
    apt-get install -y curl
  } > /dev/null
}

which parallel > /dev/null || {
  info "Install GNU parallel" && {
    apt-get install -y parallel
  } > /dev/null
}

export -f info
export -f error
export -f progress
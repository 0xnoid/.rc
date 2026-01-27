# Wrapper to intercept Docker command where 'rm' and 'all' are present, stopping and removing all containers. Usage: 'docker rm all'
docker() {
    if [[ $1 == "rm" && $2 == "all" ]]; then
        local containers=$(command docker ps -a -q)
        if [[ -n "$containers" ]]; then
            command docker stop $containers
            command docker rm $containers
        else
            echo "No containers to remove"
        fi
    else
        command docker "$@"
    fi
}

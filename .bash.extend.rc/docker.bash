# Brings down all composes in a project OR stop+remove all containers OR stop+remove all containers where name contains {input}.
## Example: 'docker rm all postgre', 'docker compose down all myproject', 'docker rm all'
docker() {
    if [[ $1 == "compose" && $2 == "down" && $3 == "all" ]]; then
        local pattern=$4
        local projects
        
        if [[ -z "$pattern" ]]; then
            projects=$(command docker compose ls -a -q)
        else
            projects=$(command docker compose ls -a -q | grep "$pattern")
        fi
        
        if [[ -n "$projects" ]]; then
            echo "Bringing down compose projects matching: ${pattern:-all}"
            while IFS= read -r project; do
                echo "Stopping project: $project"
                command docker compose -p "$project" down
            done <<< "$projects"
        else
            echo "No compose projects to bring down"
        fi
    elif [[ $1 == "rm" && $2 == "all" ]]; then
        local pattern=$3
        local -a container_array
        
        if [[ -z "$pattern" ]]; then
            echo "Containers to stop and remove:"
            command docker ps -a --format "{{.ID}}\t{{.Names}}\t{{.Label \"com.docker.compose.project\"}}" | while IFS=$'\t' read -r id name project; do
                if [[ -n "$project" ]]; then
                    echo "$id   $name   [compose: $project]"
                else
                    echo "$id   $name"
                fi
            done
            mapfile -t container_array < <(command docker ps -a -q)
        else
            echo "Containers to stop and remove (matching: $pattern):"
            command docker ps -a --format "{{.ID}}\t{{.Names}}\t{{.Label \"com.docker.compose.project\"}}" | grep "$pattern" | while IFS=$'\t' read -r id name project; do
                if [[ -n "$project" ]]; then
                    echo "$id   $name   [compose: $project]"
                else
                    echo "$id   $name"
                fi
            done
            mapfile -t container_array < <(command docker ps -a --format "{{.ID}}\t{{.Names}}" | grep "$pattern" | awk -F'\t' '{print $1}')
        fi
        
        if [[ ${#container_array[@]} -gt 0 ]]; then
            echo ""
            command docker stop "${container_array[@]}"
            command docker rm "${container_array[@]}"
            echo "Done!"
        else
            echo "No containers to remove"
        fi
    else
        command docker "$@"
    fi
}

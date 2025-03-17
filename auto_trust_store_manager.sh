# Extract paths from Nginx/Apache config files
grep -o "ssl_trusted_certificate.*;" "$file" 2>/dev/null | while read -r line; do
    if [[ "$line" =~ ssl_trusted_certificate[[:space:]]+(.+)\; ]]; then
        path=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d "'\"")
        # Handle relative paths
        if [[ ! "$path" = /* ]]; then
            path="$(dirname "$file")/$path"
        fi
        log_debug "Found trust store path in web server config: $path"
        found_paths+=("$path")
    fi
done 
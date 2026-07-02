#!/usr/bin/env sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { printf '%b[INFO]%b %b\n' "$GREEN" "$NC" "$1" >&2; }
warn() { printf '%b[WARN]%b %b\n' "$YELLOW" "$NC" "$1" >&2; }
error() { printf '%b[ERROR]%b %b\n' "$RED" "$NC" "$1" >&2; exit 1; }

# Detect shell
detect_shell() {
    case "${SHELL:-}" in
        */zsh) echo "zsh" ;;
        */bash) echo "bash" ;;
        *)
            if [ -n "${ZSH_VERSION:-}" ]; then
                echo "zsh"
            elif [ -n "${BASH_VERSION:-}" ]; then
                echo "bash"
            else
                error "Unsupported shell: ${SHELL:-unknown}. Only bash and zsh are supported."
            fi
            ;;
    esac
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect WSL
is_wsl() {
    [ -n "${WSL_DISTRO_NAME:-}" ] && return 0
    [ -r /proc/sys/kernel/osrelease ] && grep -Eqi 'microsoft|wsl' /proc/sys/kernel/osrelease
}

# Interactive yes/no prompt. Reads from /dev/tty to avoid stdin issues.
prompt_yes_no() {
    local prompt="$1"
    local response=""

    warn "$prompt [y/N]"

    if [ -r /dev/tty ]; then
        if IFS= read -r response </dev/tty; then
            :
        else
            response=""
        fi
    fi

    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# Install git if needed
install_git() {
    if prompt_yes_no "Git is not installed. Would you like to install it?"; then
        info "Installing git..."
        if command_exists apt-get; then
            sudo apt-get update && sudo apt-get install -y git
        elif command_exists yum; then
            sudo yum install -y git
        elif command_exists dnf; then
            sudo dnf install -y git
        elif command_exists pacman; then
            sudo pacman -S --noconfirm git
        elif command_exists brew; then
            brew install git
        else
            error "Unable to detect package manager. Please install git manually."
        fi
    else
        error "Git is required for installation. Exiting."
    fi
}

# download select folders from github api
download_github_dir() {
    local shell_type="$1"
    local dir="$2"
    local required="$3"
    local tool="$4"
    local api_url="https://api.github.com/repos/0xnoid/.rc/contents"
    local tmp_urls=""
    local filename=""
    local url=""

    mkdir -p "$dir"
    tmp_urls=$(mktemp "${TMPDIR:-/tmp}/rc-urls.XXXXXX") || error "Unable to create temporary file."

    if [ "$tool" = "curl" ]; then
        if ! curl -fsSL "$api_url/$dir" \
            | grep -o '"download_url": *"[^"]*"' \
            | sed 's/"download_url": *"\([^"]*\)"/\1/' > "$tmp_urls"; then
            rm -f "$tmp_urls"
            [ "$required" = "optional" ] && return 0
            error "Failed to list $dir from GitHub."
        fi
    else
        if ! wget -qO- "$api_url/$dir" \
            | grep -o '"download_url": *"[^"]*"' \
            | sed 's/"download_url": *"\([^"]*\)"/\1/' > "$tmp_urls"; then
            rm -f "$tmp_urls"
            [ "$required" = "optional" ] && return 0
            error "Failed to list $dir from GitHub."
        fi
    fi

    if [ ! -s "$tmp_urls" ]; then
        rm -f "$tmp_urls"
        [ "$required" = "optional" ] && return 0
        error "No downloadable files found in $dir."
    fi

    while IFS= read -r url; do
        [ -n "$url" ] || continue
        filename=$(basename "$url")
        if [ "$tool" = "curl" ]; then
            curl -fsSL "$url" -o "$dir/$filename"
        else
            wget -q "$url" -O "$dir/$filename"
        fi
    done < "$tmp_urls"

    rm -f "$tmp_urls"
}

# actual download (via git/curl/wget, whichever available)
download_files() {
    local shell_type="$1"
    local repo_url="https://github.com/0xnoid/.rc"
    local temp_dir=""

    temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/rc-install.XXXXXX") || error "Unable to create temporary directory."

    info "Downloading configuration files for $shell_type..."

    cd "$temp_dir" || error "Unable to enter temporary directory: $temp_dir"

    if command_exists git; then
        info "Using git for sparse checkout..."

        # surpress branch warning cos it's not aesthetic af
        git -c init.defaultBranch=master init -q >/dev/null
        git remote add origin "$repo_url" >/dev/null
        git config core.sparseCheckout true >/dev/null

        mkdir -p .git/info
        {
            echo ".global.extend.rc/"
            if [ "$shell_type" = "zsh" ]; then
                echo ".zsh.extend.rc/"
            else
                echo ".bash.extend.rc/"
            fi
            if is_wsl; then
                echo ".wsl.extend.rc/"
            fi
        } > .git/info/sparse-checkout

        git pull -q --depth=1 origin master >/dev/null

    elif command_exists curl; then
        info "Using curl for download..."
        download_with_curl "$shell_type"

    elif command_exists wget; then
        info "Using wget for download..."
        download_with_wget "$shell_type"

    else
        error "No download tool available (git, curl, or wget). Cannot proceed."
    fi

    printf '%s\n' "$temp_dir"
}

# curl
download_with_curl() {
    local shell_type="$1"

    download_github_dir "$shell_type" ".global.extend.rc" "required" "curl"

    if [ "$shell_type" = "zsh" ]; then
        download_github_dir "$shell_type" ".zsh.extend.rc" "required" "curl"
    else
        download_github_dir "$shell_type" ".bash.extend.rc" "required" "curl"
    fi

    if is_wsl; then
        download_github_dir "$shell_type" ".wsl.extend.rc" "optional" "curl"
    fi
}

# wget
download_with_wget() {
    local shell_type="$1"

    download_github_dir "$shell_type" ".global.extend.rc" "required" "wget"

    if [ "$shell_type" = "zsh" ]; then
        download_github_dir "$shell_type" ".zsh.extend.rc" "required" "wget"
    else
        download_github_dir "$shell_type" ".bash.extend.rc" "required" "wget"
    fi

    if is_wsl; then
        download_github_dir "$shell_type" ".wsl.extend.rc" "optional" "wget"
    fi
}

# copy to shell target dir
copy_extend_dir() {
    local source_dir="$1"
    local target_dir="$2"
    local shell_type="$3"
    local convert_global_rc="$4"
    local extension=".$shell_type"
    local file=""
    local filename=""
    local new_filename=""

    [ -d "$source_dir" ] || return 0

    for file in "$source_dir"/*; do
        [ -f "$file" ] || continue

        filename=$(basename "$file")

        if [ "$convert_global_rc" = "yes" ]; then
            case "$filename" in
                *.rc)
                    new_filename="$(basename "$file" .rc)$extension"
                    info "Copying $filename -> $new_filename"
                    cp "$file" "$target_dir/$new_filename"
                    ;;
                *)
                    info "Copying $filename"
                    cp "$file" "$target_dir/$filename"
                    ;;
            esac
        else
            info "Copying $filename"
            cp "$file" "$target_dir/$filename"
        fi
    done
}

# rename/merge files
process_files() {
    local shell_type="$1"
    local temp_dir="$2"
    local target_dir="$HOME/.${shell_type}.extend.rc"

    info "Processing configuration files..."

    cd "$temp_dir" || error "Unable to enter temporary directory: $temp_dir"

    mkdir -p "$target_dir"

    copy_extend_dir ".global.extend.rc" "$target_dir" "$shell_type" "yes"

    if [ "$shell_type" = "zsh" ]; then
        copy_extend_dir ".zsh.extend.rc" "$target_dir" "$shell_type" "no"
    else
        copy_extend_dir ".bash.extend.rc" "$target_dir" "$shell_type" "no"
    fi

    # wsl specifics
    if is_wsl; then
        copy_extend_dir ".wsl.extend.rc" "$target_dir" "$shell_type" "no"
    fi

    printf '%s\n' "$target_dir"
}

# update rc
update_rc_file() {
    local shell_type="$1"
    local rc_file="$HOME/.${shell_type}rc"
    local extend_dir="$HOME/.${shell_type}.extend.rc"

    info "Updating $rc_file..."

    touch "$rc_file"

    if grep -q "# Source extended RC files" "$rc_file"; then
        warn "RC sourcing already configured in $rc_file"
        return 0
    fi

    cat >> "$rc_file" << RC_BLOCK_EOF

# Source extended RC files
if [ -d "$extend_dir" ]; then
    for rc_file in "$extend_dir"/*.$shell_type; do
        if [ -f "\$rc_file" ]; then
            . "\$rc_file"
        fi
    done
    unset rc_file
fi
RC_BLOCK_EOF

    info "Successfully updated $rc_file"
}

# cleaning time
cleanup() {
    local temp_dir="${1:-}"
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        info "Cleaning up temporary files..."
        rm -rf -- "$temp_dir"
    fi
}

# main exec
main() {
    local shell_type=""
    local temp_dir=""
    local target_dir=""

    trap 'cleanup "$temp_dir"' EXIT HUP INT TERM

    info "Starting RC configuration installer..."

    shell_type=$(detect_shell)
    info "Detected shell: $shell_type"

    if ! command_exists git && ! command_exists curl && ! command_exists wget; then
        install_git
    fi

    temp_dir=$(download_files "$shell_type")
    target_dir=$(process_files "$shell_type" "$temp_dir")

    update_rc_file "$shell_type"

    info "Installation complete!"
    info "Configuration installed to: $target_dir"
    info "Please run: ${YELLOW}source ~/.${shell_type}rc${NC} or restart your shell"
}

main "$@"

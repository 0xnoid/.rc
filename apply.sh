#!/usr/bin/env sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; exit 1; }

# Detect shell
detect_shell() {
    if [ -n "$ZSH_VERSION" ]; then
        echo "zsh"
    elif [ -n "$BASH_VERSION" ]; then
        echo "bash"
    else
        # Check user's default shell
        case "$SHELL" in
            */zsh) echo "zsh" ;;
            */bash) echo "bash" ;;
            *) error "Unsupported shell: $SHELL. Only bash and zsh are supported." ;;
        esac
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install git if needed
install_git() {
    warn "Git is not installed. Would you like to install it? [y/N]"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
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
            ;;
        *)
            error "Git is required for installation. Exiting."
            ;;
    esac
}

# Download with git
download_files() {
    local shell_type="$1"
    local repo_url="https://github.com/0xnoid/.rc"
    local temp_dir="/tmp/rc-install-$$"

    info "Downloading configuration files for $shell_type..."

    mkdir -p "$temp_dir"
    cd "$temp_dir"

    if command_exists git; then
        info "Using git for sparse checkout..."
        git init
        git remote add origin "$repo_url"
        git config core.sparseCheckout true

        # Configure sparse checkout
        mkdir -p .git/info
        {
            echo ".global.extend.rc/"
            if [ "$shell_type" = "zsh" ]; then
                echo ".zsh.extend.rc/"
            else
                echo ".bash.extend.rc/"
            fi
        } > .git/info/sparse-checkout

        git pull origin master

    elif command_exists curl; then
        info "Using curl for download..."
        download_with_curl "$shell_type" "$repo_url"

    elif command_exists wget; then
        info "Using wget for download..."
        download_with_wget "$shell_type" "$repo_url"

    else
        error "No download tool available (git, curl, or wget). Cannot proceed."
    fi

    echo "$temp_dir"
}

# Download with curl
download_with_curl() {
    local shell_type="$1"
    local repo_url="$2"
    local api_url="https://api.github.com/repos/0xnoid/.rc/contents"

    mkdir -p .global.extend.rc
    curl -fsSL "$api_url/.global.extend.rc" |         grep -o '"download_url": *"[^"]*"' |         sed 's/"download_url": *"\([^"]*\)"/\1/' |         while read -r url; do
            filename=$(basename "$url")
            curl -fsSL "$url" -o ".global.extend.rc/$filename"
        done

    # Download shell-specific files
    if [ "$shell_type" = "zsh" ]; then
        mkdir -p .zsh.extend.rc
        curl -fsSL "$api_url/.zsh.extend.rc" |             grep -o '"download_url": *"[^"]*"' |             sed 's/"download_url": *"\([^"]*\)"/\1/' |             while read -r url; do
                filename=$(basename "$url")
                curl -fsSL "$url" -o ".zsh.extend.rc/$filename"
            done
    else
        mkdir -p .bash.extend.rc
        curl -fsSL "$api_url/.bash.extend.rc" |             grep -o '"download_url": *"[^"]*"' |             sed 's/"download_url": *"\([^"]*\)"/\1/' |             while read -r url; do
                filename=$(basename "$url")
                curl -fsSL "$url" -o ".bash.extend.rc/$filename"
            done
    fi
}

download_with_wget() {
    local shell_type="$1"
    local repo_url="$2"
    local api_url="https://api.github.com/repos/0xnoid/.rc/contents"

    mkdir -p .global.extend.rc
    wget -qO- "$api_url/.global.extend.rc" |         grep -o '"download_url": *"[^"]*"' |         sed 's/"download_url": *"\([^"]*\)"/\1/' |         while read -r url; do
            filename=$(basename "$url")
            wget -q "$url" -O ".global.extend.rc/$filename"
        done

    if [ "$shell_type" = "zsh" ]; then
        mkdir -p .zsh.extend.rc
        wget -qO- "$api_url/.zsh.extend.rc" |             grep -o '"download_url": *"[^"]*"' |             sed 's/"download_url": *"\([^"]*\)"/\1/' |             while read -r url; do
                filename=$(basename "$url")
                wget -q "$url" -O ".zsh.extend.rc/$filename"
            done
    else
        mkdir -p .bash.extend.rc
        wget -qO- "$api_url/.bash.extend.rc" |             grep -o '"download_url": *"[^"]*"' |             sed 's/"download_url": *"\([^"]*\)"/\1/' |             while read -r url; do
                filename=$(basename "$url")
                wget -q "$url" -O ".bash.extend.rc/$filename"
            done
    fi
}

# Rename and merge files
process_files() {
    local shell_type="$1"
    local temp_dir="$2"
    local target_dir="$HOME/.${shell_type}.extend.rc"
    local extension=".$shell_type"

    info "Processing configuration files..."

    cd "$temp_dir"

    mkdir -p "$target_dir"

    if [ -d ".global.extend.rc" ]; then
        for file in .global.extend.rc/*.rc; do
            if [ -f "$file" ]; then
                filename=$(basename "$file" .rc)
                new_filename="${filename}${extension}"
                info "Copying $(basename "$file") -> $new_filename"
                cp "$file" "$target_dir/$new_filename"
            fi
        done
    fi

    # Copy shell-specific files
    if [ "$shell_type" = "zsh" ] && [ -d ".zsh.extend.rc" ]; then
        for file in .zsh.extend.rc/*; do
            if [ -f "$file" ]; then
                info "Copying $(basename "$file")"
                cp "$file" "$target_dir/"
            fi
        done
    elif [ "$shell_type" = "bash" ] && [ -d ".bash.extend.rc" ]; then
        for file in .bash.extend.rc/*; do
            if [ -f "$file" ]; then
                info "Copying $(basename "$file")"
                cp "$file" "$target_dir/"
            fi
        done
    fi

    echo "$target_dir"
}

# Update RC file
update_rc_file() {
    local shell_type="$1"
    local rc_file="$HOME/.${shell_type}rc"
    local extend_dir="$HOME/.${shell_type}.extend.rc"

    info "Updating $rc_file..."

    # Create RC file if it doesn't exist
    touch "$rc_file"

    # Check if source block already exists
    if grep -q "# Source extended RC files" "$rc_file"; then
        warn "RC sourcing already configured in $rc_file"
        return
    fi

    # Append sourcing logic
    cat >> "$rc_file" << EOF

# Source extended RC files
if [ -d "$extend_dir" ]; then
    for rc_file in "$extend_dir"/*.$shell_type; do
        if [ -f "\$rc_file" ]; then
            . "\$rc_file"
        fi
    done
    unset rc_file
fi
EOF

    info "Successfully updated $rc_file"
}

# Cleanup
cleanup() {
    local temp_dir="$1"
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        info "Cleaning up temporary files..."
        rm -rf "$temp_dir"
    fi
}

# Main execution
main() {
    info "Starting RC configuration installer..."

    # Detect shell
    SHELL_TYPE=$(detect_shell)
    info "Detected shell: $SHELL_TYPE"

    # Check for download tools
    if ! command_exists git && ! command_exists curl && ! command_exists wget; then
        install_git
    fi

    # Download files
    TEMP_DIR=$(download_files "$SHELL_TYPE")

    # Process and install files
    TARGET_DIR=$(process_files "$SHELL_TYPE" "$TEMP_DIR")

    # Update RC file
    update_rc_file "$SHELL_TYPE"

    # Cleanup
    cleanup "$TEMP_DIR"

    info "${GREEN}Installation complete!${NC}"
    info "Configuration installed to: $TARGET_DIR"
    info "Please run: ${YELLOW}source ~/.${SHELL_TYPE}rc${NC} or restart your shell"

    # Offer to source immediately
    warn "Would you like to source your .${SHELL_TYPE}rc now? [y/N]"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            info "Sourcing ~/.${SHELL_TYPE}rc..."
            # shellcheck disable=SC1090
            . "$HOME/.${SHELL_TYPE}rc"
            info "Done! Your shell configuration is now active."
            ;;
        *)
            info "Skipped. Run 'source ~/.${SHELL_TYPE}rc' when ready."
            ;;
    esac
}

# Run main function
main

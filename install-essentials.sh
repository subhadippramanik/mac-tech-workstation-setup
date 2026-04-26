#!/usr/bin/env bash

set -uo pipefail

APP_DIR="${HOME}/Applications"
SUDO_KEEPALIVE_PID=""
INSTALL_ERRORS=()
SHOW_GITHUB_SSH_KEY=0
GITHUB_SSH_PUBLIC_KEY=""

COLOR_GREEN="\033[32m"
COLOR_YELLOW="\033[33m"
COLOR_RESET="\033[0m"

header() {
    echo "============================================================"
    echo "MacOS Interactive Installer"
    echo "Installs by category:"
    echo "  [Core Setup]          Homebrew, Git, Google Chrome, Ulaa"
    echo "  [Development Tools]   VS Code, iTerm2, zsh, Oh My Zsh, Python, Golang, Bruno"
    echo "  [Productivity]        Raycast, Freeplane, GanttProject, Adobe Acrobat Reader"
    echo "  [Drivers & Hardware]  DisplayLink Manager"
    echo "  [AI Tools]            AnythingLLM, Ollama"
    echo "Feedback or tool requests: https://github.com/subhadippramanik/mac-tech-workstation-setup"
    echo "============================================================"
}

color_green() {
    printf "%b%s%b" "$COLOR_GREEN" "$1" "$COLOR_RESET"
}

color_yellow() {
    printf "%b%s%b" "$COLOR_YELLOW" "$1" "$COLOR_RESET"
}

installed_msg() {
    local software_name="$1"
    echo "$(color_green "$software_name") is already installed."
}

installed_with_version_msg() {
    local software_name="$1"
    local version_value="$2"
    echo "$(color_green "$software_name") is already installed: ${version_value}"
}

install_completed_msg() {
    local software_name="$1"
    echo "$(color_green "$software_name") installed."
}

confirm_install_prompt() {
    local software_name="$1"
    confirm "$(color_yellow "$software_name") is not installed. Install now?"
}

confirm() {
    local prompt="$1"
    while true; do
        read -r -p "$prompt [y/n]: " choice
        case "${choice}" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
            *) echo "Please enter y or n." ;;
        esac
    done
}

is_installed_cmd() {
    command -v "$1" >/dev/null 2>&1
}

has_command_line_tools() {
    xcode-select -p >/dev/null 2>&1
}

app_installed() {
    local app_name="$1"
    [[ -d "/Applications/${app_name}.app" || -d "${APP_DIR}/${app_name}.app" ]]
}

install_cask() {
    local cask_name="$1"
    brew install --cask --appdir="$APP_DIR" "$cask_name"
}

attempt_install() {
    local label="$1"
    shift

    if "$@"; then
        return 0
    fi

    echo "[ERROR] ${label} installation failed. Continuing..."
    INSTALL_ERRORS+=("${label}")
    return 0
}

print_error_summary() {
    echo
    echo "================ Install Summary ================"
    if [[ ${#INSTALL_ERRORS[@]} -eq 0 ]]; then
        echo "All selected installations completed successfully."
        return
    fi

    echo "Completed with errors in the following items:"
    for item in "${INSTALL_ERRORS[@]}"; do
        echo -e "\033[31m- ${item}\033[0m"
    done
    echo "You can re-run the script and install only the failed items."
}

start_sudo_keepalive() {
    mkdir -p "$APP_DIR"

    echo "Requesting administrator access once so installs do not repeatedly prompt..."
    sudo -v

    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" || exit
    done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
}

ensure_command_line_tools() {
    if has_command_line_tools; then
        installed_msg "Xcode Command Line Tools"
        return
    fi

    echo "Xcode Command Line Tools are required before installing Homebrew and Git."
    echo "Opening the macOS installer now..."
    xcode-select --install || true
    echo "Finish the Command Line Tools installation in the dialog that opened, then re-run this script."
    exit 0
}

cleanup() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
        kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
    fi
}

install_homebrew() {
    if is_installed_cmd brew; then
        installed_msg "Homebrew"
        return
    fi

    ensure_command_line_tools

    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1

    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

require_brew() {
    if ! is_installed_cmd brew; then
        echo "Homebrew is required for this step. Install Homebrew first."
        return 1
    fi
    return 0
}

has_github_ssh_key() {
    [[ -f "${HOME}/.ssh/id_ed25519" && -f "${HOME}/.ssh/id_ed25519.pub" ]]
}

ensure_github_ssh_key() {
    local ssh_dir="${HOME}/.ssh"
    local ssh_config="${ssh_dir}/config"
    local key_path="${ssh_dir}/id_ed25519"
    local key_pub_path="${key_path}.pub"
    local key_email

    if has_github_ssh_key; then
        return 0
    fi

    key_email="$(git config --get user.email 2>/dev/null || true)"
    if [[ -z "$key_email" ]]; then
        key_email="your_email@example.com"
    fi

    echo "No SSH key found. Creating and configuring a GitHub SSH key..."
    mkdir -p "$ssh_dir" || return 1
    chmod 700 "$ssh_dir" || return 1

    ssh-keygen -t ed25519 -f "$key_path" -N "" || return 1
    eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
    ssh-add --apple-use-keychain "$key_path" || return 1

    if ! grep -Eq '^Host[[:space:]]+github\.com([[:space:]]|$)' "$ssh_config" 2>/dev/null; then
        {
            echo ""
            echo "Host github.com"
            echo "  AddKeysToAgent yes"
            echo "  UseKeychain yes"
            echo "  IdentityFile ~/.ssh/id_ed25519"
        } >> "$ssh_config" || return 1
    fi

    chmod 600 "$ssh_config" 2>/dev/null || true

    if [[ -f "$key_pub_path" ]]; then
        GITHUB_SSH_PUBLIC_KEY="$(cat "$key_pub_path")"
        if [[ -n "$GITHUB_SSH_PUBLIC_KEY" ]]; then
            SHOW_GITHUB_SSH_KEY=1
        fi
    fi

    return 0
}

print_github_ssh_section() {
    if [[ "$SHOW_GITHUB_SSH_KEY" -ne 1 ]]; then
        return
    fi

    echo
    echo "================ GitHub SSH Key Setup ================"
    echo "Add this public key to GitHub:"
    echo
    echo "$GITHUB_SSH_PUBLIC_KEY"
    echo
    echo "Go to GitHub:"
    echo "Settings -> SSH and GPG keys -> New SSH key"
    echo "Paste the copied key and save."
    echo "======================================================="
}

has_homebrew_python() {
    is_installed_cmd brew && brew list --versions python >/dev/null 2>&1
}

configure_python_commands() {
    local zshrc_path="${HOME}/.zshrc"
    local python_path_line='export PATH="$(brew --prefix)/opt/python/libexec/bin:$PATH"'
    local python_alias_line='alias python=python3'
    local pip_alias_line='alias pip=pip3'

    require_brew || return 1

    if ! grep -Fqx "$python_path_line" "$zshrc_path" 2>/dev/null; then
        echo "$python_path_line" >> "$zshrc_path" || return 1
        echo "Added python/pip PATH config to ${zshrc_path}."
    else
        echo "python/pip PATH config already exists in ${zshrc_path}."
    fi

    if ! grep -Fqx "$python_alias_line" "$zshrc_path" 2>/dev/null; then
        echo "$python_alias_line" >> "$zshrc_path" || return 1
        echo "Added python alias to ${zshrc_path}."
    else
        echo "python alias already exists in ${zshrc_path}."
    fi

    if ! grep -Fqx "$pip_alias_line" "$zshrc_path" 2>/dev/null; then
        echo "$pip_alias_line" >> "$zshrc_path" || return 1
        echo "Added pip alias to ${zshrc_path}."
    else
        echo "pip alias already exists in ${zshrc_path}."
    fi

    export PATH="$(brew --prefix)/opt/python/libexec/bin:$PATH"
    hash -r
}

install_git() {
    if is_installed_cmd git; then
        installed_with_version_msg "Git" "$(git --version)"
        return
    fi

    ensure_command_line_tools

    require_brew || return
    echo "Installing Git..."
    brew install git || return 1
    install_completed_msg "Git"
}

install_vscode() {
    if app_installed "Visual Studio Code"; then
        installed_msg "VS Code"
        return
    fi

    require_brew || return
    echo "Installing VS Code..."
    install_cask visual-studio-code || return 1
    install_completed_msg "VS Code"
}

install_iterm2() {
    if app_installed "iTerm"; then
        installed_msg "iTerm2"
        return
    fi

    require_brew || return
    echo "Installing iTerm2..."
    install_cask iterm2 || return 1
    install_completed_msg "iTerm2"
}

install_zsh() {
    if is_installed_cmd zsh; then
        installed_with_version_msg "zsh" "$(zsh --version)"
        return
    fi

    require_brew || return
    echo "Installing zsh..."
    brew install zsh || return 1
    install_completed_msg "zsh"
}

install_oh_my_zsh() {
    local oh_my_zsh_dir="${HOME}/.oh-my-zsh"

    if [[ -d "$oh_my_zsh_dir" ]]; then
        installed_msg "Oh My Zsh"
        return
    fi

    if ! is_installed_cmd zsh; then
        echo "zsh is required before installing Oh My Zsh. Install zsh first."
        return
    fi

    if ! is_installed_cmd git; then
        echo "Git is required before installing Oh My Zsh. Install Git first."
        return
    fi

    if ! is_installed_cmd curl; then
        echo "curl is required before installing Oh My Zsh."
        return
    fi

    echo "Installing Oh My Zsh..."
    RUNZSH=no KEEP_ZSHRC=yes CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || return 1
    echo "$(color_green "Oh My Zsh") installed. Open a new terminal window or run: zsh"
}

install_python() {
    if has_homebrew_python; then
        installed_with_version_msg "Homebrew Python" "$(python3 --version)"
        configure_python_commands || return 1
        if is_installed_cmd python && is_installed_cmd pip; then
            echo "$(color_green "python") and $(color_green "pip") commands are available."
        fi
        return
    fi

    require_brew || return
    echo "Installing Python..."
    brew install python || return 1
    configure_python_commands || return 1
    install_completed_msg "Python 3"
    if is_installed_cmd python && is_installed_cmd pip; then
        echo "$(color_green "python") and $(color_green "pip") commands are available."
    else
        echo "$(color_green "python3")/$(color_green "pip3") are installed. Open a new terminal to use python/pip without the 3 suffix."
    fi
}

install_golang() {
    if is_installed_cmd go; then
        installed_with_version_msg "Golang" "$(go version)"
        return
    fi

    require_brew || return
    echo "Installing Golang..."
    brew install go || return 1
    install_completed_msg "Golang"
}

install_raycast() {
    if app_installed "Raycast"; then
        installed_msg "Raycast"
        return
    fi

    require_brew || return
    echo "Installing Raycast..."
    install_cask raycast || return 1
    install_completed_msg "Raycast"
}

install_chrome() {
    if app_installed "Google Chrome"; then
        installed_msg "Google Chrome"
        return
    fi

    require_brew || return
    echo "Installing Google Chrome..."
    install_cask google-chrome || return 1
    install_completed_msg "Google Chrome"
}

install_ulaa() {
    if app_installed "Ulaa"; then
        installed_msg "Ulaa"
        return
    fi

    require_brew || return
    echo "Installing Ulaa..."
    install_cask ulaa || return 1
    install_completed_msg "Ulaa"
}

install_freeplane() {
    if app_installed "Freeplane"; then
        installed_msg "Freeplane"
        return
    fi

    require_brew || return
    echo "Installing Freeplane..."
    if install_cask freeplane; then
        install_completed_msg "Freeplane"
        return
    fi

    echo "Freeplane install failed. Retrying after Homebrew metadata refresh (helps with occasional HTTP 403)."
    brew update >/dev/null 2>&1 || true
    HOMEBREW_CURL_RETRIES=5 install_cask freeplane || return 1
    install_completed_msg "Freeplane"
}

install_ganttproject() {
    if app_installed "GanttProject"; then
        installed_msg "GanttProject"
        return
    fi

    require_brew || return
    echo "Installing GanttProject..."
    install_cask ganttproject || return 1
    install_completed_msg "GanttProject"
}

install_acrobat() {
    if app_installed "Adobe Acrobat Reader"; then
        installed_msg "Adobe Acrobat Reader"
        return
    fi

    require_brew || return
    echo "Installing Adobe Acrobat Reader..."
    install_cask adobe-acrobat-reader || return 1
    install_completed_msg "Adobe Acrobat Reader"
}

install_displaylink() {
    if app_installed "DisplayLink Manager"; then
        installed_msg "DisplayLink Manager"
        return
    fi

    require_brew || return
    echo "Installing DisplayLink Manager..."
    install_cask displaylink || return 1
    install_completed_msg "DisplayLink Manager"
}

install_anythingllm() {
    if app_installed "AnythingLLM"; then
        installed_msg "AnythingLLM"
        return
    fi

    require_brew || return
    echo "Installing AnythingLLM..."
    install_cask anythingllm || return 1
    install_completed_msg "AnythingLLM"
}

install_ollama() {
    if is_installed_cmd ollama; then
        installed_msg "Ollama"
        return
    fi

    require_brew || return
    echo "Installing Ollama..."
    brew install ollama || return 1
    install_completed_msg "Ollama"
}

install_bruno() {
    if app_installed "Bruno"; then
        installed_msg "Bruno"
        return
    fi

    require_brew || return
    echo "Installing Bruno..."
    install_cask bruno || return 1
    install_completed_msg "Bruno"
}

main() {
    trap cleanup EXIT
    header
    start_sudo_keepalive
    ensure_command_line_tools

    echo
    echo "[Core Setup]"

    if is_installed_cmd brew; then
        installed_msg "Homebrew"
    elif confirm_install_prompt "Homebrew"; then
        attempt_install "Homebrew" install_homebrew
    fi

    if is_installed_cmd git; then
        installed_with_version_msg "Git" "$(git --version)"
    elif confirm_install_prompt "Git"; then
        attempt_install "Git" install_git
    fi

    if has_github_ssh_key; then
        echo "$(color_green "GitHub SSH key") is already configured."
    elif confirm "$(color_yellow "GitHub SSH key") is not configured. Set it up now?"; then
        attempt_install "GitHub SSH Key" ensure_github_ssh_key
    fi

    if app_installed "Google Chrome"; then
        installed_msg "Google Chrome"
    elif confirm_install_prompt "Google Chrome"; then
        attempt_install "Google Chrome" install_chrome
    fi

    if app_installed "Ulaa"; then
        installed_msg "Ulaa"
    elif confirm_install_prompt "Ulaa"; then
        attempt_install "Ulaa" install_ulaa
    fi

    echo
    echo "[Development Tools]"

    if app_installed "Visual Studio Code"; then
        installed_msg "VS Code"
    elif confirm_install_prompt "VS Code"; then
        attempt_install "VS Code" install_vscode
    fi

    if app_installed "iTerm"; then
        installed_msg "iTerm2"
    elif confirm_install_prompt "iTerm2"; then
        attempt_install "iTerm2" install_iterm2
    fi

    if is_installed_cmd zsh; then
        installed_with_version_msg "zsh" "$(zsh --version)"
    elif confirm_install_prompt "zsh"; then
        attempt_install "zsh" install_zsh
    fi

    if [[ -d "${HOME}/.oh-my-zsh" ]]; then
        installed_msg "Oh My Zsh"
    elif confirm_install_prompt "Oh My Zsh"; then
        attempt_install "Oh My Zsh" install_oh_my_zsh
    fi

    if has_homebrew_python; then
        installed_with_version_msg "Homebrew Python" "$(python3 --version)"
    elif confirm_install_prompt "Python 3"; then
        attempt_install "Python 3" install_python
    fi

    if is_installed_cmd go; then
        installed_with_version_msg "Golang" "$(go version)"
    elif confirm_install_prompt "Golang"; then
        attempt_install "Golang" install_golang
    fi

    if app_installed "Bruno"; then
        installed_msg "Bruno"
    elif confirm_install_prompt "Bruno"; then
        attempt_install "Bruno" install_bruno
    fi

    echo
    echo "[Productivity]"

    if app_installed "Raycast"; then
        installed_msg "Raycast"
    elif confirm_install_prompt "Raycast"; then
        attempt_install "Raycast" install_raycast
    fi

    if app_installed "Freeplane"; then
        installed_msg "Freeplane"
    elif confirm_install_prompt "Freeplane"; then
        attempt_install "Freeplane" install_freeplane
    fi

    if app_installed "GanttProject"; then
        installed_msg "GanttProject"
    elif confirm_install_prompt "GanttProject"; then
        attempt_install "GanttProject" install_ganttproject
    fi

    if app_installed "Adobe Acrobat Reader"; then
        installed_msg "Adobe Acrobat Reader"
    elif confirm_install_prompt "Adobe Acrobat Reader"; then
        attempt_install "Adobe Acrobat Reader" install_acrobat
    fi

    echo
    echo "[Drivers & Hardware]"

    if app_installed "DisplayLink Manager"; then
        installed_msg "DisplayLink Manager"
    elif confirm_install_prompt "DisplayLink Manager"; then
        attempt_install "DisplayLink Manager" install_displaylink
    fi

    echo
    echo "[AI Tools]"

    if app_installed "AnythingLLM"; then
        installed_msg "AnythingLLM"
    elif confirm_install_prompt "AnythingLLM"; then
        attempt_install "AnythingLLM" install_anythingllm
    fi

    if is_installed_cmd ollama; then
        installed_msg "Ollama"
    elif confirm_install_prompt "Ollama"; then
        attempt_install "Ollama" install_ollama
    fi

    print_error_summary
    print_github_ssh_section
    echo "Done."
}

main

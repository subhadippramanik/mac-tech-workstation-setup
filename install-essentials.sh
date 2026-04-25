#!/usr/bin/env bash

set -uo pipefail

APP_DIR="${HOME}/Applications"
SUDO_KEEPALIVE_PID=""
INSTALL_ERRORS=()

header() {
    echo "============================================================"
    echo "MacOS Interactive Installer"
    echo "Installs by category:"
    echo "  [Core Setup]          Homebrew, Git, Google Chrome"
    echo "  [Development Tools]   VS Code, iTerm2, zsh, Oh My Zsh, Python, Golang, Bruno"
    echo "  [Productivity]        Raycast, Freeplane, GanttProject, Adobe Acrobat Reader"
    echo "  [Drivers & Hardware]  DisplayLink Manager"
    echo "  [AI Tools]            AnythingLLM"
    echo "============================================================"
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
        echo "Xcode Command Line Tools are already installed."
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
        echo "Homebrew is already installed."
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
        echo "Git is already installed: $(git --version)"
        return
    fi

    ensure_command_line_tools

    require_brew || return
    echo "Installing Git..."
    brew install git || return 1
    echo "Installed: $(git --version)"
}

install_vscode() {
    if app_installed "Visual Studio Code"; then
        echo "VS Code is already installed."
        return
    fi

    require_brew || return
    echo "Installing VS Code..."
    install_cask visual-studio-code || return 1
    echo "VS Code installed."
}

install_iterm2() {
    if app_installed "iTerm"; then
        echo "iTerm2 is already installed."
        return
    fi

    require_brew || return
    echo "Installing iTerm2..."
    install_cask iterm2 || return 1
    echo "iTerm2 installed."
}

install_zsh() {
    if is_installed_cmd zsh; then
        echo "zsh is already available: $(zsh --version)"
        return
    fi

    require_brew || return
    echo "Installing zsh..."
    brew install zsh || return 1
    echo "Installed: $(zsh --version)"
}

install_oh_my_zsh() {
    local oh_my_zsh_dir="${HOME}/.oh-my-zsh"

    if [[ -d "$oh_my_zsh_dir" ]]; then
        echo "Oh My Zsh is already installed."
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
    echo "Oh My Zsh installed. Open a new terminal window or run: zsh"
}

install_python() {
    if has_homebrew_python; then
        echo "Homebrew Python is already installed: $(python3 --version)"
        configure_python_commands || return 1
        if is_installed_cmd python && is_installed_cmd pip; then
            echo "python and pip commands are available."
        fi
        return
    fi

    require_brew || return
    echo "Installing Python..."
    brew install python || return 1
    configure_python_commands || return 1
    echo "Installed: $(python3 --version)"
    if is_installed_cmd python && is_installed_cmd pip; then
        echo "python and pip commands are available."
    else
        echo "python3/pip3 are installed. Open a new terminal to use python/pip without the 3 suffix."
    fi
}

install_golang() {
    if is_installed_cmd go; then
        echo "Golang is already installed: $(go version)"
        return
    fi

    require_brew || return
    echo "Installing Golang..."
    brew install go || return 1
    echo "Installed: $(go version)"
}

install_raycast() {
    if app_installed "Raycast"; then
        echo "Raycast is already installed."
        return
    fi

    require_brew || return
    echo "Installing Raycast..."
    install_cask raycast || return 1
    echo "Raycast installed."
}

install_chrome() {
    if app_installed "Google Chrome"; then
        echo "Google Chrome is already installed."
        return
    fi

    require_brew || return
    echo "Installing Google Chrome..."
    install_cask google-chrome || return 1
    echo "Google Chrome installed."
}

install_freeplane() {
    if app_installed "Freeplane"; then
        echo "Freeplane is already installed."
        return
    fi

    require_brew || return
    echo "Installing Freeplane..."
    if install_cask freeplane; then
        echo "Freeplane installed."
        return
    fi

    echo "Freeplane install failed. Retrying after Homebrew metadata refresh (helps with occasional HTTP 403)."
    brew update >/dev/null 2>&1 || true
    HOMEBREW_CURL_RETRIES=5 install_cask freeplane || return 1
    echo "Freeplane installed."
}

install_ganttproject() {
    if app_installed "GanttProject"; then
        echo "GanttProject is already installed."
        return
    fi

    require_brew || return
    echo "Installing GanttProject..."
    install_cask ganttproject || return 1
    echo "GanttProject installed."
}

install_acrobat() {
    if app_installed "Adobe Acrobat Reader"; then
        echo "Adobe Acrobat Reader is already installed."
        return
    fi

    require_brew || return
    echo "Installing Adobe Acrobat Reader..."
    install_cask adobe-acrobat-reader || return 1
    echo "Adobe Acrobat Reader installed."
}

install_displaylink() {
    if app_installed "DisplayLink Manager"; then
        echo "DisplayLink Manager is already installed."
        return
    fi

    require_brew || return
    echo "Installing DisplayLink Manager..."
    install_cask displaylink || return 1
    echo "DisplayLink Manager installed."
}

install_anythingllm() {
    if app_installed "AnythingLLM"; then
        echo "AnythingLLM is already installed."
        return
    fi

    require_brew || return
    echo "Installing AnythingLLM..."
    install_cask anythingllm || return 1
    echo "AnythingLLM installed."
}

install_bruno() {
    if app_installed "Bruno"; then
        echo "Bruno is already installed."
        return
    fi

    require_brew || return
    echo "Installing Bruno..."
    install_cask bruno || return 1
    echo "Bruno installed."
}

main() {
    trap cleanup EXIT
    header
    start_sudo_keepalive
    ensure_command_line_tools

    echo
    echo "[Core Setup]"

    if is_installed_cmd brew; then
        echo "Homebrew is already installed."
    elif confirm "Homebrew is not installed. Install now?"; then
        attempt_install "Homebrew" install_homebrew
    fi

    if is_installed_cmd git; then
        echo "Git is already installed: $(git --version)"
    elif confirm "Git is not installed. Install now?"; then
        attempt_install "Git" install_git
    fi

    if app_installed "Google Chrome"; then
        echo "Google Chrome is already installed."
    elif confirm "Google Chrome is not installed. Install now?"; then
        attempt_install "Google Chrome" install_chrome
    fi

    echo
    echo "[Development Tools]"

    if app_installed "Visual Studio Code"; then
        echo "VS Code is already installed."
    elif confirm "VS Code is not installed. Install now?"; then
        attempt_install "VS Code" install_vscode
    fi

    if app_installed "iTerm"; then
        echo "iTerm2 is already installed."
    elif confirm "iTerm2 is not installed. Install now?"; then
        attempt_install "iTerm2" install_iterm2
    fi

    if is_installed_cmd zsh; then
        echo "zsh is already available: $(zsh --version)"
    elif confirm "zsh is not installed. Install now?"; then
        attempt_install "zsh" install_zsh
    fi

    if [[ -d "${HOME}/.oh-my-zsh" ]]; then
        echo "Oh My Zsh is already installed."
    elif confirm "Oh My Zsh is not installed. Install now?"; then
        attempt_install "Oh My Zsh" install_oh_my_zsh
    fi

    if has_homebrew_python; then
        echo "Homebrew Python is already installed: $(python3 --version)"
    elif confirm "Python 3 is not installed. Install now?"; then
        attempt_install "Python 3" install_python
    fi

    if is_installed_cmd go; then
        echo "Golang is already installed: $(go version)"
    elif confirm "Golang is not installed. Install now?"; then
        attempt_install "Golang" install_golang
    fi

    if app_installed "Bruno"; then
        echo "Bruno is already installed."
    elif confirm "Bruno is not installed. Install now?"; then
        attempt_install "Bruno" install_bruno
    fi

    echo
    echo "[Productivity]"

    if app_installed "Raycast"; then
        echo "Raycast is already installed."
    elif confirm "Raycast is not installed. Install now?"; then
        attempt_install "Raycast" install_raycast
    fi

    if app_installed "Freeplane"; then
        echo "Freeplane is already installed."
    elif confirm "Freeplane is not installed. Install now?"; then
        attempt_install "Freeplane" install_freeplane
    fi

    if app_installed "GanttProject"; then
        echo "GanttProject is already installed."
    elif confirm "GanttProject is not installed. Install now?"; then
        attempt_install "GanttProject" install_ganttproject
    fi

    if app_installed "Adobe Acrobat Reader"; then
        echo "Adobe Acrobat Reader is already installed."
    elif confirm "Adobe Acrobat Reader is not installed. Install now?"; then
        attempt_install "Adobe Acrobat Reader" install_acrobat
    fi

    echo
    echo "[Drivers & Hardware]"

    if app_installed "DisplayLink Manager"; then
        echo "DisplayLink Manager is already installed."
    elif confirm "DisplayLink Manager is not installed. Install now?"; then
        attempt_install "DisplayLink Manager" install_displaylink
    fi

    echo
    echo "[AI Tools]"

    if app_installed "AnythingLLM"; then
        echo "AnythingLLM is already installed."
    elif confirm "AnythingLLM is not installed. Install now?"; then
        attempt_install "AnythingLLM" install_anythingllm
    fi

    print_error_summary
    echo "Done."
}

main

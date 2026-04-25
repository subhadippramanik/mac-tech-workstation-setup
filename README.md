# developer-mac-setup

Interactive setup scripts for a new macOS development machine.

## What is in this repo

- `install-essentials.sh`: interactive installer for common tools and apps

## Before you start

1. Complete your company-managed Mac onboarding first.
2. Download this repository or copy the scripts to your machine.
3. Open Terminal and `cd` into the repository folder.

## Main installer

Run the interactive installer:

```bash
chmod +x install-essentials.sh
./install-essentials.sh
```

The script asks for confirmation before each install.

## What the script does

- Checks for Xcode Command Line Tools and opens the macOS installer if they are missing
- Requests administrator access once at the start and keeps it alive while the script runs
- Installs GUI apps into `$HOME/Applications` to reduce repeated admin prompts
- Skips tools that are already installed

## Install categories

### Core Setup

- Homebrew
- Git
- Google Chrome

### Development Tools

- Visual Studio Code
- iTerm2
- zsh
- Oh My Zsh
- Python 3
- Golang
- Bruno

### Productivity

- Raycast
- Freeplane
- Adobe Acrobat Reader

### Drivers & Hardware

- DisplayLink Manager

### AI Tools

- AnythingLLM

## Notes

- DisplayLink Manager may still require additional macOS approval after installation.
- Some apps can ask for first-launch permissions even if installation succeeds without extra prompts.

Oh My Zsh is available directly inside `install-essentials.sh`. It keeps your current `.zshrc` and does not change your default shell automatically.

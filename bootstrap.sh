#!/usr/bin/env bash
set -euo pipefail

# Require Bash 4+ (macOS ships 3.2 which lacks fractional read -t, local -a, etc.)
if (( BASH_VERSINFO[0] < 4 )); then
  if ! command -v brew &>/dev/null; then
    echo "Bash ${BASH_VERSION} is too old. Installing Homebrew + modern Bash..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
    brew install bash
  fi
  BREW_BASH="$(brew --prefix)/bin/bash"
  if [[ ! -x "$BREW_BASH" ]]; then
    brew install bash
  fi
  exec "$BREW_BASH" "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

# Restore cursor on any exit (Ctrl+C, error, normal exit)
trap 'tput cnorm 2>/dev/null' EXIT

# ─── Colors ───────────────────────────────────────────────────────────────────

BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RESET='\033[0m'

# ─── Interactive prompt helpers ──────────────────────────────────────────────

# Multi-select with arrow-key navigation, checkboxes, and back support.
#
# Args:  header  show_back  preselected_indices  option1 option2 ...
# Sets:  SELECTED (array of 0-based indices)
#        PROMPT_ACTION  ("continue" | "back")
prompt_multi_select() {
  local header="$1" show_back="$2" preselected="$3"
  shift 3
  local options=("$@")
  local num_options=${#options[@]}

  # Build selection state from preselected string ("0 2 4" or "")
  local -a sel=()
  for ((i = 0; i < num_options; i++)); do sel[$i]=0; done
  for idx in $preselected; do
    if (( idx >= 0 && idx < num_options )); then sel[$idx]=1; fi
  done

  local num_nav=1; $show_back && num_nav=2
  local total=$((num_options + num_nav))
  local cursor=0
  local last_rendered=0 render_num=0 last_esc=0

  # Header (static — not re-rendered)
  echo ""
  echo -e "${BOLD}${header}${RESET}"
  echo -e "${DIM}↑↓ Navigate  Enter/Space Toggle  Backspace Deselect  Esc Cancel${RESET}"
  echo ""

  tput civis  # hide terminal cursor

  _render() {
    if (( render_num > 0 )); then printf "\033[${last_rendered}A"; fi
    local lines=0

    for ((i = 0; i < num_options; i++)); do
      local m="[ ]"; if (( sel[i] )); then m="[x]"; fi
      local p="  "; if (( cursor == i )); then p="> "; fi
      printf " %s %s %s\033[K\n" "$p" "$m" "${options[$i]}"
      lines=$((lines + 1))
    done

    printf "   ────────────────────────\033[K\n"; lines=$((lines + 1))

    local p="  "; if (( cursor == num_options )); then p="> "; fi
    printf " %s Continue →\033[K\n" "$p"; lines=$((lines + 1))

    if $show_back; then
      p="  "; if (( cursor == num_options + 1 )); then p="> "; fi
      printf " %s ← Back\033[K\n" "$p"; lines=$((lines + 1))
    fi

    # Buffer lines (overwrite stale cancel prompt)
    printf "\033[K\n\033[K\n"; lines=$((lines + 2))

    last_rendered=$lines; render_num=$((render_num + 1))
  }

  _render

  while true; do
    IFS= read -rsn1 key

    case "$key" in
      $'\x1b')  # ESC or escape sequence
        read -rsn1 -t 0.2 next || true
        if [[ "$next" == "[" ]]; then
          read -rsn1 arrow || true
          case "$arrow" in
            A) if (( cursor > 0 )); then cursor=$((cursor - 1)); _render; fi ;;
            B) if (( cursor < total - 1 )); then cursor=$((cursor + 1)); _render; fi ;;
            '3') # Delete key (ESC[3~)
              read -rsn1 _ || true
              if (( cursor < num_options )); then sel[$cursor]=0; _render; fi ;;
          esac
        else
          local now; now=$(date +%s)
          if (( now - last_esc <= 1 )); then tput cnorm; echo ""; exit 1; fi
          last_esc=$now
          tput cnorm
          printf "\r  Cancel bootstrap? (y/n) \033[K"
          IFS= read -rsn1 confirm
          if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then echo ""; exit 1; fi
          printf "\n"; last_rendered=$((last_rendered + 1))
          tput civis; _render
        fi
        ;;
      ''|' ')  # Enter or Space
        if (( cursor < num_options )); then
          sel[$cursor]=$(( 1 - sel[cursor] )); _render
        elif (( cursor == num_options )); then
          SELECTED=()
          for ((i = 0; i < num_options; i++)); do
            if (( sel[i] )); then SELECTED+=("$i"); fi
          done
          PROMPT_ACTION="continue"; tput cnorm; return
        elif (( cursor == num_options + 1 )); then
          PROMPT_ACTION="back"; tput cnorm; return
        fi
        ;;
      $'\x7f'|$'\x08')  # Backspace
        if (( cursor < num_options )); then sel[$cursor]=0; _render; fi
        ;;
    esac
  done
}

# Single-select with radio buttons.
#
# Args:  header  show_back  preselected_index  option1 option2 ...
# Sets:  SELECTED_ONE (0-based index, or -1)
#        PROMPT_ACTION  ("continue" | "back")
prompt_single_select() {
  local header="$1" show_back="$2" preselected="$3"
  shift 3
  local options=("$@")
  local num_options=${#options[@]}
  local sel_idx=$preselected

  local num_nav=1; $show_back && num_nav=2
  local total=$((num_options + num_nav))
  local cursor=0
  local last_rendered=0 render_num=0 last_esc=0

  echo ""
  echo -e "${BOLD}${header}${RESET}"
  echo -e "${DIM}↑↓ Navigate  Enter/Space Select  Backspace Deselect  Esc Cancel${RESET}"
  echo ""

  tput civis

  _render() {
    if (( render_num > 0 )); then printf "\033[${last_rendered}A"; fi
    local lines=0

    for ((i = 0; i < num_options; i++)); do
      local m="( )"; if (( sel_idx == i )); then m="(*)"; fi
      local p="  "; if (( cursor == i )); then p="> "; fi
      printf " %s %s %s\033[K\n" "$p" "$m" "${options[$i]}"
      lines=$((lines + 1))
    done

    printf "   ────────────────────────\033[K\n"; lines=$((lines + 1))

    local p="  "; if (( cursor == num_options )); then p="> "; fi
    printf " %s Continue →\033[K\n" "$p"; lines=$((lines + 1))

    if $show_back; then
      p="  "; if (( cursor == num_options + 1 )); then p="> "; fi
      printf " %s ← Back\033[K\n" "$p"; lines=$((lines + 1))
    fi

    printf "\033[K\n\033[K\n"; lines=$((lines + 2))
    last_rendered=$lines; render_num=$((render_num + 1))
  }

  _render

  while true; do
    IFS= read -rsn1 key

    case "$key" in
      $'\x1b')
        read -rsn1 -t 0.2 next || true
        if [[ "$next" == "[" ]]; then
          read -rsn1 arrow || true
          case "$arrow" in
            A) if (( cursor > 0 )); then cursor=$((cursor - 1)); _render; fi ;;
            B) if (( cursor < total - 1 )); then cursor=$((cursor + 1)); _render; fi ;;
            '3') read -rsn1 _ || true
              if (( cursor < num_options )); then sel_idx=-1; _render; fi ;;
          esac
        else
          local now; now=$(date +%s)
          if (( now - last_esc <= 1 )); then tput cnorm; echo ""; exit 1; fi
          last_esc=$now
          tput cnorm
          printf "\r  Cancel bootstrap? (y/n) \033[K"
          IFS= read -rsn1 confirm
          if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then echo ""; exit 1; fi
          printf "\n"; last_rendered=$((last_rendered + 1))
          tput civis; _render
        fi
        ;;
      ''|' ')
        if (( cursor < num_options )); then
          sel_idx=$cursor; _render
        elif (( cursor == num_options )); then
          SELECTED_ONE=$sel_idx; PROMPT_ACTION="continue"; tput cnorm; return
        elif (( cursor == num_options + 1 )); then
          PROMPT_ACTION="back"; tput cnorm; return
        fi
        ;;
      $'\x7f'|$'\x08')
        if (( cursor < num_options )); then sel_idx=-1; _render; fi
        ;;
    esac
  done
}

# ─── Welcome banner ──────────────────────────────────────────────────────────

clear
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║            omakase-mac                   ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"
echo -e "  This script will set up your Mac for development."
echo -e "  You'll pick your stack, IDE, browser, and apps."
echo ""
echo -e "${DIM}  Opinionated defaults (always installed):${RESET}"
echo "  Homebrew, Git, mise, Bun, Oh My Zsh, JetBrains Mono,"
echo "  Karabiner Elements, Hammerspoon, f.lux"
echo ""
if $DRY_RUN; then
  echo -e "  ${YELLOW}Running in dry-run mode — nothing will be installed.${RESET}"
  echo ""
fi
read -rp "  Press Enter to continue..."

# ─── Data definitions ────────────────────────────────────────────────────────

STACK_NAMES=("Ruby + Rails" "Node.js + TypeScript" "Python + Django" "Go" "Rust" "PHP + Laravel" "Java")

IDE_NAMES=("VS Code" "JetBrains (auto-matched to your stacks)" "Zed" "Cursor")

BROWSER_NAMES=("Firefox" "Firefox Developer Edition" "Google Chrome" "Arc" "Microsoft Edge (😂)")
BROWSER_CASKS=("firefox" "firefox@developer-edition" "google-chrome" "arc" "microsoft-edge")

VPN_NAMES=("NordVPN" "ExpressVPN" "ProtonVPN")
VPN_CASKS=("nordvpn" "expressvpn" "protonvpn")

AI_NAMES=("Claude Code" "Claude Desktop" "ChatGPT" "Ollama")
AI_CASKS=("" "claude" "chatgpt" "ollama")  # index 0 installed via bun

COMM_NAMES=("Slack" "Zoom")
COMM_CASKS=("slack" "zoom")

UTIL_NAMES=("Docker Desktop" "TablePlus" "Notion" "Obsidian" "Postman" "Insomnia" "RapidAPI (Paw)")
UTIL_CASKS=("docker" "tableplus" "notion" "obsidian" "postman" "insomnia" "rapidapi")

# ─── Interactive step loop ────────────────────────────────────────────────────

STEP=1
CHOSEN_STACKS=()
CHOSEN_IDE=-1
CHOSEN_BROWSERS=()
CHOSEN_VPNS=()
CHOSEN_AI=()
CHOSEN_COMMS=()
CHOSEN_UTILS=()

while (( STEP <= 7 )); do
  case $STEP in
    1)
      prompt_multi_select "Step 1/7 — Language stacks:" false \
        "${CHOSEN_STACKS[*]-}" "${STACK_NAMES[@]}"
      case "$PROMPT_ACTION" in
        continue) CHOSEN_STACKS=("${SELECTED[@]+"${SELECTED[@]}"}"); STEP=$((STEP + 1)) ;;
      esac
      ;;
    2)
      prompt_single_select "Step 2/7 — IDE:" true \
        "$CHOSEN_IDE" "${IDE_NAMES[@]}"
      case "$PROMPT_ACTION" in
        continue) CHOSEN_IDE=$SELECTED_ONE; STEP=$((STEP + 1)) ;;
        back) STEP=$((STEP - 1)) ;;
      esac
      ;;
    3)
      prompt_multi_select "Step 3/7 — Browsers:" true \
        "${CHOSEN_BROWSERS[*]-}" "${BROWSER_NAMES[@]}"
      case "$PROMPT_ACTION" in
        continue) CHOSEN_BROWSERS=("${SELECTED[@]+"${SELECTED[@]}"}"); STEP=$((STEP + 1)) ;;
        back) STEP=$((STEP - 1)) ;;
      esac
      ;;
    4)
      prompt_multi_select "Step 4/7 — VPN:" true \
        "${CHOSEN_VPNS[*]-}" "${VPN_NAMES[@]}"
      case "$PROMPT_ACTION" in
        continue) CHOSEN_VPNS=("${SELECTED[@]+"${SELECTED[@]}"}"); STEP=$((STEP + 1)) ;;
        back) STEP=$((STEP - 1)) ;;
      esac
      ;;
    5)
      prompt_multi_select "Step 5/7 — AI tooling:" true \
        "${CHOSEN_AI[*]-}" "${AI_NAMES[@]}"
      case "$PROMPT_ACTION" in
        continue) CHOSEN_AI=("${SELECTED[@]+"${SELECTED[@]}"}"); STEP=$((STEP + 1)) ;;
        back) STEP=$((STEP - 1)) ;;
      esac
      ;;
    6)
      prompt_multi_select "Step 6/7 — Communication:" true \
        "${CHOSEN_COMMS[*]-}" "${COMM_NAMES[@]}"
      case "$PROMPT_ACTION" in
        continue) CHOSEN_COMMS=("${SELECTED[@]+"${SELECTED[@]}"}"); STEP=$((STEP + 1)) ;;
        back) STEP=$((STEP - 1)) ;;
      esac
      ;;
    7)
      prompt_multi_select "Step 7/7 — Utilities & Productivity:" true \
        "${CHOSEN_UTILS[*]-}" "${UTIL_NAMES[@]}"
      case "$PROMPT_ACTION" in
        continue) CHOSEN_UTILS=("${SELECTED[@]+"${SELECTED[@]}"}"); STEP=$((STEP + 1)) ;;
        back) STEP=$((STEP - 1)) ;;
      esac
      ;;
  esac
done

# Derive flags from selections
INSTALL_CLAUDE_CODE=false
for idx in "${CHOSEN_AI[@]}"; do
  if (( idx == 0 )); then INSTALL_CLAUDE_CODE=true; fi
done

ANY_STACK=false
if (( ${#CHOSEN_STACKS[@]} > 0 )); then ANY_STACK=true; fi

# ─── Summary ──────────────────────────────────────────────────────────────────

summary_section() {
  local label="$1" names_var="$2" indices_var="$3"
  eval "local names=(\"\${${names_var}[@]}\")"
  eval "local indices=(\"\${${indices_var}[@]+"\${${indices_var}[@]}"}\")"

  echo -e "${BOLD}  ${label}:${RESET}"
  if (( ${#indices[@]} > 0 )); then
    for idx in "${indices[@]}"; do echo "    - ${names[$idx]}"; done
  else
    echo "    (none)"
  fi
}

echo ""
echo -e "${BOLD}══════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Ready to install. Here's the summary:${RESET}"
echo -e "${BOLD}══════════════════════════════════════════${RESET}"
echo ""

summary_section "Stacks" STACK_NAMES CHOSEN_STACKS

echo -e "${BOLD}  IDE:${RESET}"
if (( CHOSEN_IDE >= 0 )); then
  echo "    - ${IDE_NAMES[$CHOSEN_IDE]}"
else
  echo "    (none)"
fi

summary_section "Browsers" BROWSER_NAMES CHOSEN_BROWSERS
summary_section "VPN" VPN_NAMES CHOSEN_VPNS
summary_section "AI" AI_NAMES CHOSEN_AI
summary_section "Communication" COMM_NAMES CHOSEN_COMMS
summary_section "Utilities" UTIL_NAMES CHOSEN_UTILS

echo ""
read -rp "  Press Enter to start installation (Ctrl+C to abort)..."
echo ""

# ─── Install opinionated base ────────────────────────────────────────────────

if $DRY_RUN; then
  echo -e "${DIM}==> [dry-run] Would install Xcode Command Line Tools${RESET}"
  echo -e "${DIM}==> [dry-run] Would install Homebrew${RESET}"
  echo -e "${DIM}==> [dry-run] Would update Homebrew${RESET}"
else
  echo "==> Installing Xcode Command Line Tools"
  if ! xcode-select -p &>/dev/null; then
    xcode-select --install
    echo "    Waiting for Xcode CLT installation to complete..."
    until xcode-select -p &>/dev/null; do sleep 5; done
  else
    echo "    Already installed."
  fi

  echo "==> Installing Homebrew"
  if ! command -v brew &>/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    echo "    Already installed."
  fi

  echo "==> Updating Homebrew"
  brew update && brew upgrade
fi

# ─── Generate Brewfile ────────────────────────────────────────────────────────

echo "==> Generating Brewfile"

BREWFILE="$SCRIPT_DIR/Brewfile"

cat > "$BREWFILE" <<'BREW_BASE'
# ─── Base (always installed) ──────────────────────────
tap "oven-sh/bun"
brew "git"
brew "mise"
brew "bun"
brew "gh"

# ─── CLI power tools ─────────────────────────────────
brew "fzf"
brew "ripgrep"
brew "jq"
brew "bat"
brew "eza"
brew "zoxide"
brew "trash"
brew "tldr"
brew "lazygit"

cask "flux"
cask "karabiner-elements"
cask "hammerspoon"
cask "font-jetbrains-mono"
BREW_BASE

# Rust needs rustup via brew, PHP needs composer
for idx in "${CHOSEN_STACKS[@]}"; do
  if (( idx == 4 )); then
    echo "" >> "$BREWFILE"
    echo "# ─── Rust toolchain ─────────────────────────────────────" >> "$BREWFILE"
    echo 'brew "rustup"' >> "$BREWFILE"
  fi
  if (( idx == 5 )); then
    echo "" >> "$BREWFILE"
    echo "# ─── PHP ────────────────────────────────────────────────" >> "$BREWFILE"
    echo 'brew "composer"' >> "$BREWFILE"
  fi
done

# IDE cask
if (( CHOSEN_IDE >= 0 )); then
  echo "" >> "$BREWFILE"
  echo "# ─── IDE ──────────────────────────────────────────────────" >> "$BREWFILE"

  case $CHOSEN_IDE in
    0) echo 'cask "visual-studio-code"' >> "$BREWFILE" ;;
    1)
      JETBRAINS_ADDED=()
      for idx in "${CHOSEN_STACKS[@]}"; do
        case $idx in
          0) cask="rubymine" ;; 1) cask="webstorm" ;; 2) cask="pycharm" ;;
          3) cask="goland" ;;   4) cask="rustrover" ;; 5) cask="phpstorm" ;;
          6) cask="intellij-idea" ;; *) cask="" ;;
        esac
        if [[ -n "$cask" ]]; then
          local_dup=false
          for added in "${JETBRAINS_ADDED[@]+"${JETBRAINS_ADDED[@]}"}"; do
            [[ "$added" == "$cask" ]] && { local_dup=true; break; }
          done
          if ! $local_dup; then
            echo "cask \"$cask\"" >> "$BREWFILE"
            JETBRAINS_ADDED+=("$cask")
          fi
        fi
      done
      if (( ${#JETBRAINS_ADDED[@]} == 0 )); then echo 'cask "intellij-idea"' >> "$BREWFILE"; fi
      ;;
    2) echo 'cask "zed"' >> "$BREWFILE" ;;
    3) echo 'cask "cursor"' >> "$BREWFILE" ;;
  esac
fi

# Append casks from a category
# Usage: append_casks "Header" CASKS_ARRAY INDICES_ARRAY [skip_index]
append_casks() {
  local header="$1" casks_var="$2" indices_var="$3"
  local skip="${4:--1}"
  eval "local casks=(\"\${${casks_var}[@]}\")"
  eval "local indices=(\"\${${indices_var}[@]+"\${${indices_var}[@]}"}\")"

  if (( ${#indices[@]} == 0 )); then return; fi

  local has=false
  for idx in "${indices[@]}"; do
    if (( idx != skip )) && [[ -n "${casks[$idx]}" ]]; then has=true; break; fi
  done

  if $has; then
    echo "" >> "$BREWFILE"
    echo "# ─── ${header} ──────────────────────────────────────────" >> "$BREWFILE"
    for idx in "${indices[@]}"; do
      if (( idx != skip )) && [[ -n "${casks[$idx]}" ]]; then
        echo "cask \"${casks[$idx]}\"" >> "$BREWFILE"
      fi
    done
  fi
}

append_casks "Browsers" BROWSER_CASKS CHOSEN_BROWSERS
append_casks "VPN" VPN_CASKS CHOSEN_VPNS
append_casks "AI" AI_CASKS CHOSEN_AI 0
append_casks "Communication" COMM_CASKS CHOSEN_COMMS
append_casks "Utilities & Productivity" UTIL_CASKS CHOSEN_UTILS

echo "    Brewfile written to $BREWFILE"

if $DRY_RUN; then
  echo ""
  echo -e "${BOLD}── Generated Brewfile ──${RESET}"
  cat "$BREWFILE"
  echo ""
fi

# ─── brew bundle ──────────────────────────────────────────────────────────────

if $DRY_RUN; then
  echo -e "${DIM}==> [dry-run] Would run: brew bundle --file=$BREWFILE${RESET}"
else
  echo "==> Installing Brewfile dependencies"
  brew bundle --file="$BREWFILE"
fi

# ─── Oh My Zsh ────────────────────────────────────────────────────────────────

if $DRY_RUN; then
  echo -e "${DIM}==> [dry-run] Would install Oh My Zsh${RESET}"
  echo -e "${DIM}==> [dry-run] Would install zsh-autosuggestions plugin${RESET}"
else
  echo "==> Installing Oh My Zsh"
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    echo "    Already installed."
  fi

  echo "==> Installing zsh-autosuggestions plugin"
  ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  else
    echo "    Already installed."
  fi
fi

# ─── Generate .zshrc ─────────────────────────────────────────────────────────

echo "==> Generating .zshrc"

BASE_PLUGINS="git zsh-autosuggestions mise brew macos gh web-search fzf"
STACK_PLUGINS=""

for idx in "${CHOSEN_STACKS[@]}"; do
  case $idx in
    0) STACK_PLUGINS+=" rails bundler ruby" ;;
    1) STACK_PLUGINS+=" node npm bun" ;;
    2) STACK_PLUGINS+=" python pip" ;;
    3) STACK_PLUGINS+=" golang" ;;
    4) STACK_PLUGINS+=" rust" ;;
    5) STACK_PLUGINS+=" laravel" ;;
    6) ;;
  esac
done

ALL_PLUGINS="${BASE_PLUGINS}${STACK_PLUGINS}"
ZSHRC="$SCRIPT_DIR/dotfiles/.zshrc"

cat > "$ZSHRC" <<ZSHRC_EOF
# Oh My Zsh
export ZSH="\$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(${ALL_PLUGINS})
source "\$ZSH/oh-my-zsh.sh"

# Mise
eval "\$(mise activate zsh)"

# Zoxide (smarter cd)
eval "\$(zoxide init zsh)"

# Aliases
alias ll="eza -la --git --icons"
alias ls="eza"
alias tree="eza --tree"
alias cat="bat --paging=never"
alias lg="lazygit"
alias te="open -a TextEdit"

# Functions
mkcd() { mkdir -p "\$1" && cd "\$1"; }
ports() { lsof -iTCP -sTCP:LISTEN -n -P; }
ZSHRC_EOF

echo "    .zshrc written to $ZSHRC"

if $DRY_RUN; then
  echo ""
  echo -e "${BOLD}── Generated .zshrc ──${RESET}"
  cat "$ZSHRC"
  echo ""
fi

# ─── Symlinks ────────────────────────────────────────────────────────────────

if $DRY_RUN; then
  echo -e "${DIM}==> [dry-run] Would symlink .zshrc → $HOME/.zshrc${RESET}"
  echo -e "${DIM}==> [dry-run] Would symlink karabiner.json → $HOME/.config/karabiner/karabiner.json${RESET}"
  echo -e "${DIM}==> [dry-run] Would symlink init.lua → $HOME/.hammerspoon/init.lua${RESET}"
else
  echo "==> Symlinking .zshrc"
  if [ -f "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ]; then
    BACKUP="$HOME/.zshrc.backup.$(date +%Y%m%d%H%M%S)"
    echo "    Backing up existing .zshrc to $BACKUP"
    mv "$HOME/.zshrc" "$BACKUP"
  fi
  ln -sf "$ZSHRC" "$HOME/.zshrc"

  echo "==> Symlinking Karabiner config"
  mkdir -p "$HOME/.config/karabiner"
  ln -sf "$SCRIPT_DIR/dotfiles/karabiner.json" "$HOME/.config/karabiner/karabiner.json"

  echo "==> Symlinking Hammerspoon config"
  mkdir -p "$HOME/.hammerspoon"
  ln -sf "$SCRIPT_DIR/dotfiles/init.lua" "$HOME/.hammerspoon/init.lua"
fi

# ─── Claude Code ──────────────────────────────────────────────────────────────

if $INSTALL_CLAUDE_CODE; then
  if $DRY_RUN; then
    echo -e "${DIM}==> [dry-run] Would install Claude Code via bun${RESET}"
  else
    echo "==> Installing Claude Code"
    if ! command -v claude &>/dev/null; then
      bun install -g @anthropic-ai/claude-code
    else
      echo "    Already installed."
    fi
  fi
fi

# ─── mise installs per stack ─────────────────────────────────────────────────

if $DRY_RUN; then
  for idx in "${CHOSEN_STACKS[@]}"; do
    case $idx in
      0) echo -e "${DIM}==> [dry-run] Would install: mise ruby@3.4.8, postgres@18.1, gem install rails${RESET}" ;;
      1) echo -e "${DIM}==> [dry-run] Would install: mise node@lts, postgres@18.1, bun add -g typescript${RESET}" ;;
      2) echo -e "${DIM}==> [dry-run] Would install: mise python@3.13, postgres@18.1, pip install django${RESET}" ;;
      3) echo -e "${DIM}==> [dry-run] Would install: mise go@latest, postgres@18.1${RESET}" ;;
      4) echo -e "${DIM}==> [dry-run] Would install: rustup-init, mise postgres@18.1${RESET}" ;;
      5) echo -e "${DIM}==> [dry-run] Would install: mise php@8.4, postgres@18.1, composer global require laravel/installer${RESET}" ;;
      6) echo -e "${DIM}==> [dry-run] Would install: mise java@latest, postgres@18.1${RESET}" ;;
    esac
  done
else
  if $ANY_STACK; then
    echo "==> Installing language runtimes via mise"
  fi

  for idx in "${CHOSEN_STACKS[@]}"; do
    case $idx in
      0) echo "    Ruby 3.4.8 + PostgreSQL 18.1"
        mise use --global ruby@3.4.8; mise use --global postgres@18.1 ;;
      1) echo "    Node.js LTS + PostgreSQL 18.1"
        mise use --global node@lts; mise use --global postgres@18.1 ;;
      2) echo "    Python 3.13 + PostgreSQL 18.1"
        mise use --global python@3.13; mise use --global postgres@18.1 ;;
      3) echo "    Go (latest) + PostgreSQL 18.1"
        mise use --global go@latest; mise use --global postgres@18.1 ;;
      4) echo "    Rust (via rustup) + PostgreSQL 18.1"
        command -v rustup &>/dev/null && { rustup-init -y --no-modify-path 2>/dev/null || true; }
        mise use --global postgres@18.1 ;;
      5) echo "    PHP 8.4 + PostgreSQL 18.1"
        mise use --global php@8.4; mise use --global postgres@18.1 ;;
      6) echo "    Java (latest) + PostgreSQL 18.1"
        mise use --global java@latest; mise use --global postgres@18.1 ;;
    esac
  done

  for idx in "${CHOSEN_STACKS[@]}"; do
    case $idx in
      0) echo "==> Installing Rails"; gem install rails ;;
      1) echo "==> Installing TypeScript globally"; bun add -g typescript ;;
      2) echo "==> Installing Django"; pip install django ;;
      5) echo "==> Installing Laravel installer"; composer global require laravel/installer ;;
    esac
  done
fi

# ─── Git config ───────────────────────────────────────────────────────────────

if $DRY_RUN; then
  echo -e "${DIM}==> [dry-run] Would prompt for git name/email and configure${RESET}"
  echo -e "${DIM}==> [dry-run] Would set git defaults (defaultBranch, autoSetupRemote, rebase, global gitignore)${RESET}"
  echo -e "${DIM}==> [dry-run] Would generate SSH key and config${RESET}"
  echo -e "${DIM}==> [dry-run] Would run: gh auth login${RESET}"
else
  echo ""
  echo -e "${BOLD}==> Git configuration${RESET}"

  CURRENT_NAME=$(git config --global user.name 2>/dev/null || true)
  CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || true)

  if [[ -n "$CURRENT_NAME" ]]; then
    echo "    Current name:  $CURRENT_NAME"
    read -rp "    New name (Enter to keep): " GIT_NAME
    GIT_NAME="${GIT_NAME:-$CURRENT_NAME}"
  else
    read -rp "    Your name: " GIT_NAME
  fi

  if [[ -n "$CURRENT_EMAIL" ]]; then
    echo "    Current email: $CURRENT_EMAIL"
    read -rp "    New email (Enter to keep): " GIT_EMAIL
    GIT_EMAIL="${GIT_EMAIL:-$CURRENT_EMAIL}"
  else
    read -rp "    Your email: " GIT_EMAIL
  fi

  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"

  # Sensible git defaults
  git config --global init.defaultBranch main
  git config --global push.autoSetupRemote true
  git config --global pull.rebase true

  # Global gitignore (macOS junk, editor files)
  GLOBAL_GITIGNORE="$HOME/.gitignore_global"
  cat > "$GLOBAL_GITIGNORE" <<'GITIGNORE'
# macOS
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
Thumbs.db

# Editors
*.swp
*.swo
*~
.idea/
.vscode/
*.sublime-workspace
GITIGNORE
  git config --global core.excludesFile "$GLOBAL_GITIGNORE"
  echo "    Global gitignore written to $GLOBAL_GITIGNORE"

  # SSH key
  echo "==> Generating SSH key"
  SSH_KEY="$HOME/.ssh/id_ed25519"
  if [ ! -f "$SSH_KEY" ]; then
    ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N ""
    eval "$(ssh-agent -s)"
    ssh-add "$SSH_KEY"
    echo "    Public key:"
    cat "${SSH_KEY}.pub"
  else
    echo "    SSH key already exists at $SSH_KEY"
  fi

  # SSH config with sensible defaults
  SSH_CONFIG="$HOME/.ssh/config"
  if [ ! -f "$SSH_CONFIG" ]; then
    cat > "$SSH_CONFIG" <<'SSHCONFIG'
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
  ServerAliveInterval 60
  ServerAliveCountMax 3
SSHCONFIG
    chmod 600 "$SSH_CONFIG"
    echo "    SSH config written to $SSH_CONFIG"
  else
    echo "    SSH config already exists at $SSH_CONFIG"
  fi

  echo "==> Authenticating with GitHub"
  if ! gh auth status &>/dev/null 2>&1; then
    gh auth login
  else
    echo "    Already authenticated."
  fi
fi

# ─── macOS Defaults ───────────────────────────────────────────────────────────

if $DRY_RUN; then
  echo -e "${DIM}==> [dry-run] Would apply macOS defaults${RESET}"
else
  echo "==> Applying macOS defaults"

  # ── Keyboard ──────────────────────────────────────────
  # Blazing fast key repeat
  defaults write NSGlobalDomain KeyRepeat -int 1
  defaults write NSGlobalDomain InitialKeyRepeat -int 11
  # Hold key = repeat (not accent picker) — essential for Vim motions
  defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
  # Disable auto-correct, smart quotes/dashes, auto-capitalize, period shortcut
  defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
  defaults write NSGlobalDomain WebAutomaticSpellingCorrectionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false

  # ── Trackpad ──────────────────────────────────────────
  defaults write NSGlobalDomain com.apple.trackpad.scaling -float 2.0
  defaults write NSGlobalDomain com.apple.mouse.scaling -float 0.5
  # Tap to click
  defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
  defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true

  # ── Dock ──────────────────────────────────────────────
  defaults write com.apple.dock tilesize -int 72
  defaults write com.apple.dock autohide -bool true
  # Scale effect (faster than genie)
  defaults write com.apple.dock mineffect -string "scale"
  # Don't show recent apps
  defaults write com.apple.dock show-recents -bool false
  # Don't auto-rearrange Spaces based on recent use
  defaults write com.apple.dock mru-spaces -bool false

  # ── Finder ────────────────────────────────────────────
  # Show hidden files, file extensions, path bar, status bar
  defaults write com.apple.finder AppleShowAllFiles -bool true
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true
  defaults write com.apple.finder ShowPathbar -bool true
  defaults write com.apple.finder ShowStatusBar -bool true
  # Keep folders on top when sorting by name
  defaults write com.apple.finder _FXSortFoldersFirst -bool true
  # Default to list view
  defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

  # ── Animations ──────────────────────────────────────────
  # Full keyboard access — Tab through all UI controls
  defaults write NSGlobalDomain AppleKeyboardUIMode -int 2
  # Disable window open/close animations
  defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
  # Fast Mission Control animation
  defaults write com.apple.dock expose-animation-duration -float 0.1
  # Fast Launchpad show/hide
  defaults write com.apple.dock springboard-show-duration -float 0.1
  defaults write com.apple.dock springboard-hide-duration -float 0.1
  # Faster space switching at screen edges
  defaults write com.apple.dock workspaces-edge-delay -float 0.1
  # Instant window resize for Cocoa apps
  defaults write NSGlobalDomain NSWindowResizeTime -float 0.001

  # ── Screenshots ──────────────────────────────────────────
  mkdir -p "$HOME/Desktop/Screenshots"
  defaults write com.apple.screencapture location -string "$HOME/Desktop/Screenshots"
  defaults write com.apple.screencapture type -string "png"
  defaults write com.apple.screencapture disable-shadow -bool true

  # ── Security ──────────────────────────────────────────
  # Require password immediately after sleep/screensaver
  defaults write com.apple.screensaver askForPassword -int 1
  defaults write com.apple.screensaver askForPasswordDelay -int 0

  # ── System ────────────────────────────────────────────
  # Expand save and print panels by default
  defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
  defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
  defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
  defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
  # Disable "Are you sure you want to open this application?"
  defaults write com.apple.LaunchServices LSQuarantine -bool false

  # ── TextEdit ──────────────────────────────────────────
  # Plain text mode by default
  defaults write com.apple.TextEdit RichText -int 0
  defaults write com.apple.TextEdit PlainTextEncoding -int 4
  defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4

  # ── Safari Developer ──────────────────────────────────
  defaults write com.apple.Safari IncludeDevelopMenu -bool true
  defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true

  # ── Developer directory ───────────────────────────────
  mkdir -p "$HOME/Developer"

  # ── Spotlight: exclude ~/Developer from indexing ──────
  # Prevents Spotlight from indexing node_modules, .git, build artifacts, etc.
  if ! mdutil -s "$HOME/Developer" 2>/dev/null | grep -q "disabled"; then
    sudo mdutil -i off "$HOME/Developer" 2>/dev/null || true
  fi

  # Apply Dock & Finder changes
  killall Dock 2>/dev/null || true
  killall Finder 2>/dev/null || true
  killall SystemUIServer 2>/dev/null || true

  echo "    Applied."
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  All done! Open a new terminal to load${RESET}"
echo -e "${BOLD}${GREEN}  your configuration.${RESET}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════${RESET}"
echo ""

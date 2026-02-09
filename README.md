# omakase-mac

Opinionated, interactive Mac setup for developers. One command to install your stack, IDE, tools, and apps — chef's choice, your picks.

```bash
bash bootstrap.sh
```

## What it does

The script walks you through 7 steps to pick your stack, tools, and apps, then installs and configures everything in one go. Selections are collected upfront before anything is installed.

### Interactive UI

- Arrow keys to navigate, Enter/Space to toggle, Backspace to deselect
- `[x]` checkboxes for multi-select, `(*)` radio buttons for single-select
- `Continue ->` / `<- Back` navigation between steps
- Esc to cancel (double-Esc for immediate exit)

## Steps

### Step 1 — Language Stacks (multi-select)

| Stack               | Installed via mise             | Extras                                   | Zsh plugins       |
|---------------------|--------------------------------|------------------------------------------|--------------------|
| Ruby + Rails        | ruby@3.4.8, postgres@18.1     | `gem install rails`                      | rails, bundler, ruby |
| Node.js + TypeScript| node@lts, postgres@18.1        | `bun add -g typescript`                  | node, npm, bun     |
| Python + Django     | python@3.13, postgres@18.1     | `pip install django`                     | python, pip        |
| Go                  | go@latest, postgres@18.1       |                                          | golang             |
| Rust                | rustup (via brew), postgres@18.1 |                                        | rust               |
| PHP + Laravel       | php@8.4, postgres@18.1         | `composer global require laravel/installer` | laravel         |
| Java                | java@latest, postgres@18.1     |                                          |                    |

PostgreSQL is installed via mise if any stack is selected.

### Step 2 — IDE (single-select)

| IDE        | Cask                    | Notes                                    |
|------------|-------------------------|------------------------------------------|
| VS Code    | `visual-studio-code`    |                                          |
| JetBrains  | Auto-matched to stacks  | Ruby->RubyMine, Node->WebStorm, Python->PyCharm, Go->GoLand, Rust->RustRover, PHP->PhpStorm, Java->IntelliJ IDEA |
| Zed        | `zed`                   |                                          |
| Cursor     | `cursor`                |                                          |

### Step 3 — Browsers (multi-select)

Firefox, Firefox Developer Edition, Google Chrome, Arc, Microsoft Edge (😂)

### Step 4 — VPN (multi-select)

NordVPN, ExpressVPN, ProtonVPN

### Step 5 — AI Tooling (multi-select)

Claude Code (installed via bun), Claude Desktop, ChatGPT, Ollama

### Step 6 — Communication (multi-select)

Slack, Zoom

### Step 7 — Utilities & Productivity (multi-select)

Docker Desktop, TablePlus, Notion, Obsidian, Postman, Insomnia, RapidAPI (Paw)

## Opinionated defaults (always installed)

These are installed without prompting:

- **Xcode Command Line Tools**
- **Homebrew**
- **Git**, **mise**, **Bun**, **GitHub CLI**
- **Oh My Zsh** with robbyrussell theme + zsh-autosuggestions
- **JetBrains Mono** font
- **Karabiner Elements** + config (see [Karabiner key mappings](#karabiner-key-mappings) below)
- **Hammerspoon** + config (see [Hammerspoon shortcuts](#hammerspoon-shortcuts) below)
- **f.lux** — blue light filter

### CLI Power Tools

Installed via Homebrew alongside the base tools:

| Tool       | What it does                          | Shell alias     |
|------------|---------------------------------------|-----------------|
| `fzf`      | Fuzzy finder                          |                 |
| `ripgrep`  | Fast grep                             |                 |
| `jq`       | JSON processor                        |                 |
| `bat`      | cat with syntax highlighting          | `cat`           |
| `eza`      | Modern ls replacement                 | `ls`, `ll`, `tree` |
| `zoxide`   | Smarter cd (learns your habits)       | `z`             |
| `trash`    | Move to Trash instead of rm           |                 |
| `tldr`     | Simplified man pages                  |                 |
| `lazygit`  | Terminal UI for git                   | `lg`            |

### Shell Aliases

Added to `.zshrc`:

```bash
alias ll="eza -la --git --icons"
alias ls="eza"
alias tree="eza --tree"
alias cat="bat --paging=never"
alias lg="lazygit"
alias te="open -a TextEdit"     # open files in TextEdit

mkcd() { mkdir -p "$1" && cd "$1"; }   # create dir and cd into it
ports() { lsof -iTCP -sTCP:LISTEN -n -P; }  # show listening ports
```

### Karabiner Key Mappings

Karabiner Elements remaps keys at the OS level. The config (`dotfiles/karabiner.json`) is symlinked to `~/.config/karabiner/karabiner.json`.

**Caps Lock -> Hyper key**

Caps Lock is remapped to press Cmd+Ctrl+Option+Shift simultaneously (the "Hyper" modifier). This turns a useless key into a modifier that never conflicts with any app shortcut. Hammerspoon uses this Hyper key for all its shortcuts (see below).

**Right Cmd + IJKL -> Arrow keys**

Navigate without leaving the home row. Works everywhere in macOS — text editors, browsers, Finder, terminal. Combine with Shift for text selection, Option for word jumping.

| Shortcut       | Arrow key |
|----------------|-----------|
| Right Cmd + J  | Left      |
| Right Cmd + K  | Down      |
| Right Cmd + I  | Up        |
| Right Cmd + L  | Right     |

**Function key overrides**

| Key | Action                  |
|-----|-------------------------|
| F3  | Mission Control         |
| F4  | Launchpad               |
| F5  | Keyboard brightness down|
| F6  | Keyboard brightness up  |
| F9  | Fast forward (media)    |

### Hammerspoon Shortcuts

Hammerspoon uses the Hyper key (Caps Lock) set up by Karabiner. The config (`dotfiles/init.lua`) is symlinked to `~/.hammerspoon/init.lua`.

**Window management** (instant, no animations)

| Shortcut   | Action          |
|------------|-----------------|
| Hyper + J  | Left half       |
| Hyper + L  | Right half      |
| Hyper + I  | Maximize        |
| Hyper + K  | Custom position |

**App switching** — launch or focus with a single keystroke

| Shortcut   | App        |
|------------|------------|
| Hyper + E  | Finder     |
| Hyper + F  | Safari     |
| Hyper + T  | Terminal   |
| Hyper + M  | Mail       |
| Hyper + N  | Notes      |
| Hyper + R  | Reminders  |
| Hyper + O  | Calendar   |
| Hyper + X  | Xcode      |

**System**

| Shortcut   | Action                            |
|------------|-----------------------------------|
| Hyper + 0  | Reload Hammerspoon config         |

The Mac is also automatically muted on wake from sleep.

### macOS Defaults

The script applies these system preferences:

**Keyboard** — Fastest key repeat (1/11), hold-key repeats instead of accent picker (essential for Vim), disables auto-correct, smart quotes, smart dashes, auto-capitalize, and period shortcut.

**Trackpad** — Tracking speed 2.0, tap to click enabled.

**Dock** — Size 72, auto-hide, scale effect, no recent apps, no MRU space reordering.

**Finder** — Show hidden files, show extensions, path bar, status bar, folders first, list view default.

**Animations** — Disabled window open/close animations, fast Mission Control (0.1s), fast Launchpad, fast space switching, instant window resize, full keyboard access (Tab through all UI controls).

**Screenshots** — Saved to `~/Desktop/Screenshots/`, PNG format, no shadow.

**Security** — Password required immediately after sleep/screensaver.

**System** — Expanded save/print panels by default, disabled "Are you sure?" on app launch.

**TextEdit** — Plain text mode by default.

**Safari** — Developer menu and web inspector enabled.

**Developer** — Creates `~/Developer` directory, disables Spotlight indexing on it (no more indexing node_modules, .git, build artifacts).

### Git Configuration

- Prompts for name and email (preserves existing values)
- `init.defaultBranch = main`
- `push.autoSetupRemote = true`
- `pull.rebase = true`
- Global `.gitignore_global` (`.DS_Store`, editor files, IDE directories)

### SSH

- Generates Ed25519 key if none exists
- Creates `~/.ssh/config` with `AddKeysToAgent`, `UseKeychain`, keep-alive settings
- Authenticates with GitHub via `gh auth login`

## Dry-run mode

Test the interactive prompts and see what would be generated without installing anything:

```bash
bash bootstrap.sh --dry-run
```

This runs all 7 steps, generates the Brewfile and .zshrc, prints them to stdout, and skips all installations, symlinks, and system changes.

## Project structure

```
omakase-mac/
├── bootstrap.sh              # Main script
├── README.md
├── LICENSE
├── .gitignore
└── dotfiles/
    ├── karabiner.json         # Static — Karabiner Elements config
    └── init.lua               # Static — Hammerspoon config
```

The script generates `Brewfile` and `dotfiles/.zshrc` at runtime based on your selections (gitignored). `karabiner.json` and `init.lua` are static configs that get symlinked.

### Symlinks created

| Source                          | Target                                    |
|---------------------------------|-------------------------------------------|
| `dotfiles/.zshrc`               | `~/.zshrc`                                |
| `dotfiles/karabiner.json`       | `~/.config/karabiner/karabiner.json`      |
| `dotfiles/init.lua`             | `~/.hammerspoon/init.lua`                 |

If `~/.zshrc` already exists (and isn't a symlink), it's backed up with a timestamp before symlinking.

## Requirements

- macOS (Apple Silicon or Intel)
- Internet connection for Homebrew, Oh My Zsh, and package downloads

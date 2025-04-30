# CLI Tools

This repository contains custom CLI tools and utility scripts meant to be available system-wide.

## Structure

- `bin/`: Executable scripts (e.g., `pretty_print.sh`)
- `activate_tools.sh`: Sets up symlinks to make scripts available globally

## Setup

After cloning the repository:

```bash
git clone https://github.com/lukmay/cli-tools.git ~/dev/cli-tools
cd ~/dev/cli-tools
./activate_tools.sh
```

This creates symlinks from the `bin/` scripts to `/usr/local/bin`, making them globally executable. The script also ensures the files are executable.

## Updating

To get the latest changes or sync across systems:

```bash
cd ~/dev/cli-tools
git pull
./activate_tools.sh
```

## Notes

- Ensure `/usr/local/bin` is in your `PATH`.
- Scripts in `bin/` must have executable permissions.
```


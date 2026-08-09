# Paper server

Requires `x86_64-linux` Nix with flakes enabled:

```bash
# Foreground first run; type `stop` to exit cleanly.
nix run .#minecraft-server

# Install/start the per-user background service.
nix run .#install-minecraft-service
systemctl --user {status,restart,stop} minecraft-server

# Attach; detach with Ctrl-b d.
nix run .#console

# Refresh declared plugin JARs, then restart.
nix run .#update-plugins
systemctl --user restart minecraft-server
```

Persistent state is in `server/` (ignored by Git). Worlds, logs, and plugin/Paper configuration remain local. `flake.nix` manages Paper, memory, EULA, seed, chat-reporting setting, whitelist, operators, and `server.properties`; `plugins.nix` manages plugin JARs.

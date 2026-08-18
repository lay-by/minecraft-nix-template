{
  description = "Portable Paper Minecraft server";

  inputs = {
    nix-minecraft.url = "github:Infinidoge/nix-minecraft";
    nixpkgs.follows = "nix-minecraft/nixpkgs";
  };

  outputs = { self, nixpkgs, nix-minecraft }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      paperServer = nix-minecraft.legacyPackages.${system}.paperServers.paper-26_2;
      modrinthPrefetch = nix-minecraft.packages.${system}.nix-modrinth-prefetch;
      minecraftService = managementSystem:
        (
          nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              nix-minecraft.nixosModules.minecraft-servers
              ({ pkgs, ... }: {
                system.stateVersion = "25.11";
                services.minecraft-servers = {
                  enable = true;
                  eula = true;
                  # Only the generated service uses this path. The wrappers run
                  # its scripts from $MINECRAFT_DATA_DIR (or ./server).
                  dataDir = "/srv/minecraft";
                  servers.paper = {
                    enable = true;
                    autoStart = false;
                    restart = "no";
                    package = paperServer;
                    jvmOpts = "-Xms1G -Xmx3G";
                    serverProperties = {
                      level-seed = "7979099859567551957";
                      enforce-secure-profile = false;
                      spawn-protection = 0;
                      white-list = true;
                    };
                    # Note, /whitelist is not persistent across server restarts
                    whitelist = {
                      GingerOffender = "7979bde4-cffd-430f-9ce6-dfa7e1eae75a";
                      Astrochemistry = "76047b6d-e236-4205-8f9a-a36bf31c2582";
                      rnask = "e110db4e-e7f0-4d58-a9e7-8cf637266c4f";
                      KuceTX = "22e074ad-3eb2-4c2e-a788-4f8c0bb84b29";
                      EggyWilly = "c5c428ab-9351-4a39-aed5-f77e87761bcd";
                      WhiteWillyHarv = "16500282-057c-4e8b-934f-c584b0b3dfd7";
                    HolisticBlock96 = "fc6a41bb-14a2-4185-ab23-d3f17bd0a148";
                    Hush_h = "ab51fd8d-9f55-49f3-a12d-ea981dde53df";
                  };
                    operators.Hush_h = {
                      uuid = "ab51fd8d-9f55-49f3-a12d-ea981dde53df";
                      level = 4;
                      bypassesPlayerLimit = true;
                    };
                    symlinks = import ./plugins.nix { inherit pkgs; };
                    inherit managementSystem;
                  };
                };
              })
            ];
          }
        ).config.systemd.services.minecraft-server-paper.serviceConfig;

      foregroundService = minecraftService {
        tmux.enable = false;
        systemd-socket.enable = true;
      };
      tmuxSocket = "/tmp/minecraft-paper.sock";
      tmuxService = minecraftService {
        tmux = {
          enable = true;
          socketPath = _: tmuxSocket;
        };
      };
      tmuxStop = pkgs.lib.removeSuffix " $MAINPID" tmuxService.ExecStop;

      mkApp = name: runtimeInputs: text:
        pkgs.writeShellApplication {
          inherit name text;
          runtimeInputs = [ pkgs.coreutils ] ++ runtimeInputs;
        };

      minecraftServer = mkApp "minecraft-server" [ ] ''
        data_dir="''${MINECRAFT_DATA_DIR:-$PWD/server}"
        mkdir -p "$data_dir"
        cd "$data_dir"

        ${foregroundService.ExecStartPre}
        exec ${foregroundService.ExecStart}
      '';

      updatePlugins = mkApp "update-plugins" [ pkgs.curl pkgs.jq pkgs.nix modrinthPrefetch ] ''
        repo_dir="$(pwd -P)"
        output="$repo_dir/plugins.nix"
        temporary="$(mktemp "$repo_dir/.plugins.nix.XXXXXX")"
        trap 'rm -f "$temporary"' EXIT

        fetch_modrinth() {
          target="$1"
          project="$2"
          payload="$(curl -fsSL -G -H 'User-Agent: minecraft-flake-plugin-updater/1.0' --data-urlencode 'loaders=["paper"]' "https://api.modrinth.com/v2/project/$project/version")"
          version="$(printf '%s' "$payload" | jq -er 'map(select(.version_type == "release")) | sort_by(.date_published) | last | .id')"
          prefetch="$(nix-modrinth-prefetch "$version")"
          printf '  "%s" = pkgs.%s;\n' "$target" "$prefetch"
        }

        fetch_treeassist() {
          url="https://slipcor.net/plugins/treeassist/release/latest/TreeAssist.jar"
          hash="$(nix store prefetch-file --json --hash-type sha256 --name TreeAssist.jar "$url" | jq -er .hash)"
          printf '  "plugins/TreeAssist.jar" = pkgs.fetchurl {\n    url = "%s";\n    hash = "%s";\n  };\n' "$url" "$hash"
        }

        fetch_hangar() {
          target="$1"
          author="$2"
          project="$3"
          payload="$(curl -fsSL -H 'User-Agent: minecraft-flake-plugin-updater/1.0 (https://github.com/Infinidoge/nix-minecraft)' "https://hangar.papermc.io/api/v1/projects/$author/$project/versions")"
          url="$(printf '%s' "$payload" | jq -er '.result | map(select(.channel.name == "Release" and .downloads.PAPER.externalUrl == null)) | sort_by(.createdAt) | last | .downloads.PAPER.downloadUrl')"
          hash="$(nix store prefetch-file --json --hash-type sha256 --name "$(basename "$target")" "$url" | jq -er .hash)"
          printf '  "%s" = pkgs.fetchurl {\n    url = "%s";\n    hash = "%s";\n  };\n' "$target" "$url" "$hash"
        }

        {
          printf '%s\n' "# Generated by nix run .#update-plugins."
          printf '%s\n' "# Keys match nix-minecraft's servers.<name>.symlinks declaration format."
          printf '%s\n' '{ pkgs }:' '{'
          fetch_modrinth "plugins/EssentialsX.jar" essentialsx
          fetch_modrinth "plugins/ChestsortPlus.jar" 'chestsort%2B'
          fetch_treeassist
          fetch_hangar "plugins/CreeperConduct.jar" TheGreatCodeholio CreeperConduct
          fetch_hangar "plugins/Chunky.jar" pop4959 Chunky
          fetch_modrinth "plugins/SilkSpawners.jar" silkspawners
          fetch_modrinth "plugins/LuckPerms.jar" luckperms
          fetch_modrinth "plugins/InfiniteVillagerTrades.jar" infinite-villager-trading
          fetch_modrinth "plugins/WanderingTrades.jar" wanderingtrades
          fetch_modrinth "plugins/WorldEdit.jar" worldedit
          printf '%s\n' '}'
        } > "$temporary"

        mv "$temporary" "$output"
        echo "Updated $output. Restart the server to load the new JARs."
      '';

      minecraftTmux = mkApp "minecraft-tmux" [ pkgs.tmux ] ''
        data_dir="''${MINECRAFT_DATA_DIR:-$PWD/server}"
        case "''${1:-}" in
          start)
            mkdir -p "$data_dir"
            cd "$data_dir"
            ${tmuxService.ExecStartPre}
            exec ${tmuxService.ExecStart}
            ;;
          stop)
            cd "$data_dir"
            exec ${tmuxStop} 0
            ;;
          kill)
            tmux -S ${tmuxSocket} kill-server 2>/dev/null || true
            ;;
          *)
            echo "usage: minecraft-tmux {start|stop|kill}" >&2
            exit 64
            ;;
        esac
      '';

      minecraftConsole = mkApp "minecraft-console" [ pkgs.tmux ] ''
        exec tmux -S ${tmuxSocket} attach
      '';

      restart = mkApp "restart" [ pkgs.systemd ] ''
        exec systemctl --user restart minecraft-server
      '';

      installMinecraftService = mkApp "install-minecraft-service" [ pkgs.systemd ] ''
        repo_dir="$(pwd -P)"
        nix_bin="$(command -v nix || true)"
        unit_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
        unit_path="$unit_dir/minecraft-server.service"

        if [ -z "$nix_bin" ]; then
          echo "nix was not found in PATH" >&2
          exit 1
        fi

        mkdir -p "$unit_dir"
        cat > "$unit_path" <<EOF
        [Unit]
        Description=Paper Minecraft server
        After=network-online.target
        Wants=network-online.target

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        WorkingDirectory=$repo_dir
        ExecStart=$nix_bin run --no-write-lock-file "path:$repo_dir#minecraft-tmux" -- start
        ExecStop=$nix_bin run --no-write-lock-file "path:$repo_dir#minecraft-tmux" -- stop
        ExecStopPost=$nix_bin run --no-write-lock-file "path:$repo_dir#minecraft-tmux" -- kill
        TimeoutStopSec=10s

        [Install]
        WantedBy=default.target
        EOF

        systemctl --user daemon-reload
        systemctl --user enable --now minecraft-server.service
      '';
    in
    {
      packages.${system} = {
        minecraft-server = minecraftServer;
        minecraft-tmux = minecraftTmux;
        console = minecraftConsole;
        restart = restart;
        install-minecraft-service = installMinecraftService;
        update-plugins = updatePlugins;
        default = minecraftServer;
      };

      apps.${system} = {
        minecraft-server = {
          type = "app";
          program = "${minecraftServer}/bin/minecraft-server";
        };
        console = {
          type = "app";
          program = "${minecraftConsole}/bin/minecraft-console";
        };
        restart = {
          type = "app";
          program = "${restart}/bin/restart";
        };
        minecraft-tmux = {
          type = "app";
          program = "${minecraftTmux}/bin/minecraft-tmux";
        };
        install-minecraft-service = {
          type = "app";
          program = "${installMinecraftService}/bin/install-minecraft-service";
        };
        update-plugins = {
          type = "app";
          program = "${updatePlugins}/bin/update-plugins";
        };
      };
    };
}

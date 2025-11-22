{
  description = "Bitcoin Lightning Node on Signet (using TrustedCoin)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # --- Define paths --- #
        BASE_DIR="$HOME/.lightning-node";
        NETWORK="signet";

        paths = {
          flakeDir=toString self;
          homeDir="${BASE_DIR}";
          lightningDir="${BASE_DIR}/.lightning";
          lnbitsDir="${BASE_DIR}/lnbits";
          supervisorDir="${BASE_DIR}/supervisor";
          logDir="${BASE_DIR}/logs";
          pluginsDir="${BASE_DIR}/.lightning/${NETWORK}/plugins";
          trustedcoinDir="${BASE_DIR}/.lightning/${NETWORK}/plugins/trustedcoin";
        };

        # --- Build trustedcoin Go binary --- #
        trustedcoin = pkgs.buildGoModule rec {
          pname = "trustedcoin";
          version = "0.8.6";

          src = pkgs.fetchFromGitHub {
            owner = "nbd-wtf";
            repo = pname;
            rev = "v${version}";
            hash = "sha256-b+Icq/9qMF+Zvh7RuG9RxU8/U07Tl8ymZvNKWsZzatw=";
          };

          vendorHash = "sha256-fW+EoNPC0mH8C06Q6GXNwFdzE7oQT+qd+B7hGGml+hc=";

          subPackages = [ "." ];

          preCheck = ''
            ln -s $TMP/go/bin/trustedcoin .
          '';
        };

        # --- Create supervisord config --- #
        generateSupervisordConfig = pkgs.writeShellScriptBin "generate-supervisord-config" ''

          cat > "${paths.supervisorDir}/supervisord.conf" <<EOF
          [supervisord]
          logfile=%(here)s/supervisord.log
          logfile_maxbytes=50MB
          logfile_backups=10
          loglevel=info
          pidfile=%(here)s/supervisord.pid
          nodaemon=false
          directory=%(here)s

          [unix_http_server]
          file=%(here)s/supervisor.sock

          [supervisorctl]
          serverurl=unix://%(here)s/supervisor.sock

          [rpcinterface:supervisor]
          supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

          [program:lightningd]
          command=${pkgs.clightning}/bin/lightningd --network=${NETWORK} --lightning-dir=${paths.lightningDir}
          priority=10
          directory=${paths.homeDir}
          autostart=true
          autorestart=true
          startretries=3
          redirect_stderr=true
          stdout_logfile=${paths.logDir}/lightningd.log
          stdout_logfile_maxbytes=10MB
          stdout_logfile_backups=5
          environment=PATH="${pkgs.clightning}/bin:${trustedcoin}/bin:${pkgs.coreutils}/bin:${pkgs.gnused}/bin:${pkgs.python3}/bin:/usr/bin:/bin"
          
          [program:lnbits]
          command=${lnbitsWrapped}/bin/lnbits-run
          priority=20
          directory=%(ENV_LNBITS_DIR)s
          autostart=true
          autorestart=true
          startretries=3
          redirect_stderr=true
          stdout_logfile=%(ENV_LOG_DIR)s/lnbits.log
          stdout_logfile_maxbytes=10MB
          stdout_logfile_backups=5
          stopasgroup=true
          killasgroup=true
          environment=HOME_DIR="${paths.homeDir}",LNBITS_DIR="${paths.lnbitsDir}",LOG_DIR="${paths.logDir}",LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.secp256k1}/lib:${pkgs.openssl.dev}/lib:${pkgs.gmp}/lib:${pkgs.libffi}/lib:${pkgs.zlib}/lib"

          [program:caddy]
          command=${pkgs.caddy}/bin/caddy run --config %(ENV_HOME)s/.caddy/Caddyfile
          priority=30
          directory=%(ENV_HOME)s
          autostart=true
          autorestart=true
          startretries=3
          redirect_stderr=true
          stdout_logfile=%(ENV_paths.logDir)s/caddy.log
          stdout_logfile_maxbytes=10MB
          stdout_logfile_backups=5
          environment=PATH="${pkgs.caddy}/bin:/usr/bin:/bin",paths.logDir="${paths.logDir}"
          EOF
          
          echo "✓ Supervisord config generated at ${paths.supervisorDir}/supervisord.conf"
        '';

        # -- Setup environment & directories (one-time) --- #
        setupEnvironment = pkgs.writeShellScriptBin "setup-lightning-env" ''
          set -euo pipefail
          
          echo "Setting up Lightning Node environment..."
          echo "Home: ${paths.homeDir}";
          echo "HomeDir: ${paths.homeDir}";
          
          # -- Create directories --- #
          for dir in "${paths.homeDir}" "${paths.logDir}" "${paths.lightningDir}/${NETWORK}" "${paths.supervisorDir}"; do
            mkdir -p "$dir"
          done

          # --- Load configuration file --- #
          if [ ! -d "${paths.homeDir}/config" ] && [ -d "${paths.flakeDir}/config" ]; then
            echo "Load Lightning config..."
            cp -r ${paths.flakeDir}/config "${paths.homeDir}/config"
          fi
          
          # --- Setup Lightning config --- #
          if [ ! -f "${paths.lightningDir}/${NETWORK}/config" ] && [ -f "${paths.flakeDir}/config/lightning-config" ]; then
            echo "Copying Lightning config..."
            cat "${paths.homeDir}/config/lightning-config" > "${paths.lightningDir}/${NETWORK}/config"
          fi
          
          # --- Setup TrustedCoin plugin --- #
          if [ ! -d "${paths.pluginsDir}" ]; then
            echo "Installing TrustedCoin plugin..."
            mkdir -p "${paths.pluginsDir}"
            mkdir -p "${paths.trustedcoinDir}"
            cp ${trustedcoin}/bin/trustedcoin "${paths.trustedcoinDir}/trustedcoin"
            chmod +x "${paths.trustedcoinDir}/trustedcoin"
            echo -e "\e[32mSUCCESS: TrustedCoin plugin installed at ${paths.trustedcoinDir}/trustedcoin\e[0m"
          fi
          
          # --- Setup LNbits --- #
          if [ ! -d "${paths.lnbitsDir}" ]; then
            echo "Cloning and setting up LNbits..."
            ${pkgs.git}/bin/git clone https://github.com/lnbits/lnbits.git "${paths.lnbitsDir}"
            
            mkdir -p "${paths.lnbitsDir}/data"
            
            [[ -f "${paths.homeDir}/config/lnbits.env" ]] && cp "${paths.homeDir}/config/lnbits.env" "${paths.lnbitsDir}/.env"
            
            pushd "${paths.lnbitsDir}"
            echo "Creating Python virtual environment..."
            ${pkgs.python312}/bin/python3 -m venv .venv
            source .venv/bin/activate
            ${pkgs.poetry}/bin/poetry install --only main
            deactivate
            popd
            echo -e "\e[32mSUCCESS: LNbits installed\e[0m"
          fi
          
          # --- Generate supervisord config --- #
          echo "Generating supervisord configuration..."
          ${generateSupervisordConfig}/bin/generate-supervisord-config
          
          echo ""
          echo -e "\e[32mSUCCESS: Environment setup complete!\e[0m"
          echo ""
          echo "Next steps:"
          echo "1. Start services: lightning-start"
          echo "2. Check status: lightning-status"
          echo "3. View logs: lightning-logs"
        '';


        # --- LNbits venv wrapper --- #
        lnbitsWrapped = pkgs.writeShellScriptBin "lnbits-run" ''
          export LNBITS_DIR="${paths.homeDir}/lnbits";
          export LD_LIBRARY_PATH="${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.openssl}/lib:${pkgs.secp256k1}/lib:$LD_LIBRARY_PATH"
          
          RPC_PATH="${paths.lightningDir}/${NETWORK}/lightning-rpc"
          echo "Waiting for Core Lightning daemon to be ready..."
          until lightning-cli --rpc-file="$RPC_PATH" getinfo &>/dev/null; do
              echo "CLN not ready yet, sleeping 5s..."
              sleep 5
          done

          cd "$LNBITS_DIR"
          .venv/bin/python -m uvicorn lnbits.__main__:app --host 127.0.0.1 --port 5000
        '';


        # --- Instance Services --- #
        startServices = pkgs.writeShellScriptBin "lightning-start" ''
          set -euo pipefail

          if [ -f "${paths.supervisorDir}/supervisord.pid" ]; then
            PID=$(cat "${paths.supervisorDir}/supervisord.pid")
            if ps -p $PID > /dev/null 2>&1; then
              echo "Supervisord is already running (PID: $PID)"
              echo "Use 'lightning-status' to check services"
              exit 0
            else
              echo "Removing stale PID file..."
              rm -f "${paths.supervisorDir}/supervisord.pid"
            fi
          fi
          
          echo "Starting Lightning Node services with supervisord..."
          cd "${paths.supervisorDir}"
          ${pkgs.python3Packages.supervisor}/bin/supervisord -c "${paths.supervisorDir}/supervisord.conf"
          
          echo ""
          echo -e "\e[32mSUCCESS: Services started!\e[0m"
          echo ""
          echo "Available commands:"
          echo "  lightning-status  - Check service status"
          echo "  lightning-logs    - View all logs"
          echo "  lightning-stop    - Stop all services"
          echo "  lightning-restart - Restart a specific service"
          echo ""
          echo "Direct supervisorctl access:"
          echo "  supervisorctl -c ${paths.supervisorDir}/supervisord.conf status"
        '';

        stopServices = pkgs.writeShellScriptBin "lightning-stop" ''
          set -euo pipefail

          SUPERVISORCTL="${pkgs.python3Packages.supervisor}/bin/supervisorctl"

          if [ ! -f "${paths.supervisorDir}/supervisord.pid" ]; then
            echo "Supervisord is not running"
          else
            echo "Stopping all services..."
            cd "${paths.supervisorDir}"

            $SUPERVISORCTL -c "${paths.supervisorDir}/supervisord.conf" stop all || true
            sleep 3
            $SUPERVISORCTL -c "${paths.supervisorDir}/supervisord.conf" shutdown || true
          fi

          echo "Cleaning up any remaining processes..."

          # --- Kill LNbits (even inside virtualenv) ---
          pkill -f "lnbits.__main__" 2>/dev/null || true
          pkill -f "python.*lnbits" 2>/dev/null || true
          pkill -f "${paths.lnbitsDir}/.venv/bin/python" 2>/dev/null || true

          # --- Kill Lightning Node + Plugins ---
          pkill -f "lightningd.*${NETWORK}" 2>/dev/null || true
          pkill -f "trustedcoin" 2>/dev/null || true

          sleep 2
          REMAINING=$(pgrep -a -f "lnbits\|lightningd\|trustedcoin" || true)
          if [ -z "$REMAINING" ]; then
            echo -e "\e[32mSUCCESS: All services stopped\e[0m"
          else
            echo "⚠ Some processes are still running:"
            echo "$REMAINING"
          fi
        '';


        statusServices = pkgs.writeShellScriptBin "lightning-status" ''
          set -euo pipefail

          if [ ! -f "${paths.supervisorDir}/supervisord.pid" ]; then
            echo "Supervisord is not running"
            echo "Start it with: lightning-start"
            exit 1
          fi
          
          cd "${paths.supervisorDir}"
          ${pkgs.python3Packages.supervisor}/bin/supervisorctl -c "${paths.supervisorDir}/supervisord.conf" status
        '';

        viewLogs = pkgs.writeShellScriptBin "lightning-logs" ''
          set -euo pipefail

          echo "=== Lightning Node Logs ==="
          echo ""
          echo "Available log files:"
          echo "  1. lightningd: ${paths.logDir}/lightningd.log"
          echo "  2. lnbits: ${paths.logDir}/lnbits.log"
          echo "  3. caddy: ${paths.logDir}/caddy.log"
          echo "  4. supervisor: ${paths.supervisorDir}"
          echo ""
          echo "View a specific log with: tail -f <log-file>"
          echo ""
          
          if [ "$1" = "lightningd" ]; then
            tail -f "${paths.logDir}/lightningd.log"
          elif [ "$1" = "lnbits" ]; then
            tail -f "${paths.logDir}/lnbits.log"
          elif [ "$1" = "caddy" ]; then
            tail -f "${paths.logDir}/caddy.log"
          elif [ "$1" = "supervisor" ]; then
            tail -f "${paths.supervisorDir}/supervisord.log"
          else
            echo "Usage: lightning-logs [lightningd|lnbits|caddy|supervisor]"
            echo "Or manually: tail -f ${paths.logDir}/<service>.log"
          fi
        '';

        restartService = pkgs.writeShellScriptBin "lightning-restart" ''
          set -euo pipefail
        
          if [ -z "$1" ]; then
            echo "Usage: lightning-restart [lightningd|lnbits|caddy|all]"
            exit 1
          fi
          
          if [ ! -f "${paths.supervisorDir}/supervisord.pid" ]; then
            echo "Supervisord is not running"
            echo "Start it with: lightning-start"
            exit 1
          fi
          
          cd "${paths.supervisorDir}"
          ${pkgs.python3Packages.supervisor}/bin/supervisorctl -c "${paths.supervisorDir}/supervisord.conf" restart "$1"
        '';

      in
      {
        packages = {
          inherit trustedcoin;
          setup = setupEnvironment;
        };

        apps = {
          setup = {
            type = "app";
            program = "${setupEnvironment}/bin/setup-lightning-env";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # -- Core Lightning --- #
            clightning
            
            # --- Python 3.12 for LNbits --- #
            python312
            python312Packages.pip
            python312Packages.virtualenv
            python3Packages.supervisor
            poetry
            
            # --- Build dependencies --- #
            secp256k1
            pkg-config
            gcc
            gmp
            libffi
            openssl
            zlib
            stdenv.cc.cc.lib
            
            # --- Caddy --- #
            caddy
            
            # --- Utils --- #
            jq
            curl
            procps
            git
            
            # --- Scripts --- #
            setupEnvironment
            generateSupervisordConfig
            startServices
            stopServices
            statusServices
            viewLogs
            restartService
          ];

          shellHook = ''
            alias lightning-cli="lightning-cli --network=${NETWORK} --lightning-dir=${paths.lightningDir} "

            echo "Lightning Node ${NETWORK} Environment (Supervisord)"
            echo "================================================"
            echo ""
            if [ ! -d "${paths.lightningDir}" ]; then
              echo "Setup (first time only):"
              echo "  setup-lightning-env       - Install and configure everything"
              echo ""
            else
              echo "Service Management:"
              echo "  lightning-start           - Start all services in background"
              echo "  lightning-stop            - Stop all services"
              echo "  lightning-status          - Check service status"
              echo "  lightning-restart <name>  - Restart a service (lightningd|lnbits|caddy)"
              echo ""
              echo "Logging:"
              echo "  lightning-logs <service>  - View logs (lightningd|lnbits|caddy|supervisor)"
              echo ""
              echo "Lightning CLI:"
              echo "  lightning-cli <command>"
              echo ""
            fi
          '';
        };
      }
    );
}
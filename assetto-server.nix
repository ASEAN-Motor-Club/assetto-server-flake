{
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  cfg = config.services.assetto-server;

  discordNotify = pkgs.writeShellScript "discord-notify" ''
    WEBHOOK_URL="$1"
    MESSAGE="$2"
    ${pkgs.curl}/bin/curl -s -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "$MESSAGE" > /dev/null 2>&1 || true
  '';

  assetto-server-bin = pkgs.stdenv.mkDerivation {
    pname = "assetto-server";
    version = cfg.serverVersion;
    src = pkgs.fetchurl {
      url = "https://github.com/compujuckel/AssettoServer/releases/download/${cfg.serverVersion}/assetto-server-linux-x64.tar.gz";
      hash = "sha256-EGc0S9ipjh+jV1xDpV3MnOZPTaIK5tttozVxXkGH428=";
    };
    nativeBuildInputs = [pkgs.autoPatchelfHook];
    buildInputs = [pkgs.stdenv.cc.cc.lib pkgs.openssl pkgs.icu pkgs.zlib];
    installPhase = ''
      mkdir -p $out/bin
      cp AssettoServer $out/bin/
      cp libsteam_api.so libcsp_xxhash3.so steam_appid.txt $out/bin/
      cp -r plugins $out/bin/
      chmod +x $out/bin/AssettoServer
    '';
    meta.mainProgram = "AssettoServer";
  };

  serverCfgFile = pkgs.writeText "server_cfg.ini" ''
    [SERVER]
    NAME=${cfg.serverName}
    CARS=${concatStringsSep ";" cfg.cars}
    CONFIG_TRACK=${cfg.trackLayout}
    TRACK=${cfg.track}
    SUN_ANGLE=48
    PASSWORD=${cfg.password}
    ADMIN_PASSWORD=
    MAX_PLAYERS=${toString cfg.maxPlayers}
    UDP_PORT=${toString cfg.port}
    TCP_PORT=${toString cfg.port}
    CLIENT_SEND_INTERVAL_HZ=18
    REGISTER_TO_LOBBY=${
      if cfg.isPrivate
      then "0"
      else "1"
    }
    PICKUP_MODE=1
    LOOP_MODE=1
    SLEEP_TIME=1
    CLIENT_TIMEOUT=10
    RACE_OVER_TIME=120
    KICK_QUORUM=51
    VOTING_QUORUM=80
    VOTE_DURATION=20
    BLACKLIST_MODE=0
    NUM_THREADS=2

    [WEATHER]
    WEATHER_0=3_clear
    BASE_TEMPERATURE_AMBIENT=26
    BASE_TEMPERATURE_ROAD=10
    VARIATION_AMBIENT=1
    VARIATION_ROAD=1

    [SESSION_0]
    NAME=Practice
    TYPE=0
    DURATION=0
  '';

  entryListFile = let
    generateEntry = index: isAi: let
      carIndex = mod index (length cfg.cars);
      carModel = elemAt cfg.cars carIndex;
      skin = cfg.carSkins.${carModel} or "";
    in ''
      [CAR_${toString index}]
      MODEL=${carModel}
      SKIN=${skin}
      DRIVERNAME=
      NATIONALITY=
      TEAM=
      GUID=0
      BALLAST=0
      FIXED_SETUP=
      ${optionalString isAi "AI=auto"}
    '';
    playerEntries = concatMapStrings (i: generateEntry i false) (range 0 (cfg.maxPlayers - 1));
    aiEntries =
      optionalString (cfg.enableAi && cfg.aiTrafficSlots > 0)
      (concatMapStrings (i: generateEntry i true) (range cfg.maxPlayers (cfg.maxPlayers + cfg.aiTrafficSlots - 1)));
  in
    pkgs.writeText "entry_list.ini" (playerEntries + aiEntries);

  yamlFormat = pkgs.formats.yaml {};

  extraCfgDefaults =
    {
      WelcomeMessage = cfg.welcomeMessage;
      EnableAi = cfg.enableAi;
      ServerDescription = cfg.serverDescription;
    }
    // optionalAttrs cfg.enableAi {
      AiParams =
        {
          AiAutoFillCount = cfg.aiTrafficSlots;
        }
        // cfg.aiConfig;
    }
    // optionalAttrs (cfg.cspMinVersion != null) {
      MinimumCspVersion = cfg.cspMinVersion;
    };

  mergedExtraCfg = lib.recursiveUpdate extraCfgDefaults cfg.extraCfg;
  extraCfgFile = yamlFormat.generate "extra_cfg.yml" mergedExtraCfg;

  cspExtraOptionsFile = pkgs.writeText "csp_extra_options.ini" cfg.cspExtraOptions;

  adminsFile = pkgs.writeText "admins.txt" (concatStringsSep "\n" cfg.admins);
in {
  imports = [./logger.nix];

  options.services.assetto-server = mkOption {
    type = types.submodule (import ./backend-options.nix);
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = length cfg.cars > 0;
        message = "assetto-server: cars list must not be empty";
      }
      {
        assertion = cfg.track != "";
        message = "assetto-server: track must be set";
      }
      {
        assertion = cfg.aiTrafficSlots == 0 || cfg.enableAi;
        message = "assetto-server: aiTrafficSlots > 0 requires enableAi = true";
      }
    ];

    networking.firewall = mkIf cfg.openFirewall {
      allowedUDPPorts = [cfg.port];
    };

    users.groups.${cfg.group} = {};

    users.users.${cfg.user} = {
      isNormalUser = true;
      group = cfg.group;
    };

    systemd.services.assetto-server = {
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      restartIfChanged = false;
      description = "AssettoServer (Assetto Corsa freeroam)";
      unitConfig = mkIf (cfg.discordWebhookEnvironmentFile != null) {
        OnFailure = "assetto-server-crash-notify.service";
      };
      environment = cfg.environment;
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        Restart = "always";
        RestartSec = "10s";
        StartLimitBurst = 5;
        StartLimitIntervalSec = 300;
        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "770";
        WorkingDirectory = "/var/lib/${cfg.stateDirectory}";

        RestrictAddressFamilies = "AF_INET AF_INET6 AF_UNIX AF_NETLINK";

        CPUAffinity = cfg.cpuAffinity;
        CPUQuota = cfg.cpuQuota;
        MemoryMax = cfg.memoryMax;
        MemoryHigh = cfg.memoryHigh;
        MemorySwapMax = "0";
        OOMScoreAdjust = 500;
        Nice = toString cfg.nice;
        IOSchedulingClass = "idle";
        LimitNOFILE = "65536";
      };
      preStart = ''
        mkdir -p cfg

        cp --no-preserve=mode,ownership ${serverCfgFile} cfg/server_cfg.ini
        cp --no-preserve=mode,ownership ${entryListFile} cfg/entry_list.ini
        cp --no-preserve=mode,ownership ${extraCfgFile} cfg/extra_cfg.yml
        ${optionalString (cfg.cspExtraOptions != "") ''
          cp --no-preserve=mode,ownership ${cspExtraOptionsFile} cfg/csp_extra_options.ini
        ''}
        ${optionalString (length cfg.admins > 0) ''
          cp --no-preserve=mode,ownership ${adminsFile} cfg/admins.txt
        ''}

        ln -sfn ${cfg.contentHostPath}/content content
        ln -sfn ${assetto-server-bin}/bin/plugins plugins
        ln -sfn ${assetto-server-bin}/bin/libsteam_api.so .
        ln -sfn ${assetto-server-bin}/bin/libcsp_xxhash3.so .
        ln -sfn ${assetto-server-bin}/bin/steam_appid.txt .
      '';
      script = ''
        exec ${lib.getExe assetto-server-bin}
      '';
    };

    systemd.services.assetto-server-crash-notify = mkIf (cfg.discordWebhookEnvironmentFile != null) {
      description = "Send assetto-server crash logs to Discord";
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = cfg.discordWebhookEnvironmentFile;
      };
      path = [pkgs.systemd pkgs.coreutils pkgs.gnused pkgs.jq];
      script = ''
        set -euo pipefail

        JOURNAL_LOGS=$(journalctl -u assetto-server.service -n 50 --no-pager --output=short 2>&1 || echo "(failed to read journal)")
        JOURNAL_LOGS=$(echo "$JOURNAL_LOGS" | tail -c 900)

        PAYLOAD=$(jq -n \
          --arg journal "$JOURNAL_LOGS" \
          '{
            embeds: [{
              title: "💥 assetto-server crashed",
              color: 14495300,
              fields: [
                { name: "📋 Server Journal (last lines)", value: ("```\n" + $journal + "\n```") }
              ]
            }]
          }')

        ${discordNotify} "$DISCORD_ERRORS_WEBHOOK" "$PAYLOAD"
      '';
    };

    systemd.services.assetto-server-restart = {
      enable = cfg.restartSchedule != null;
      description = "AssettoServer Restart";
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        systemctl restart assetto-server
      '';
    };

    systemd.timers.assetto-server-restart = {
      enable = cfg.restartSchedule != null;
      description = "Timer to restart AssettoServer";
      timerConfig = {
        OnCalendar = cfg.restartSchedule;
        AccuracySec = "1min";
        Unit = "assetto-server-restart.service";
      };
      wantedBy = ["timers.target"];
    };

    services.assetto-server-logger = {
      enable = cfg.enableLogStreaming;
      serverLogsPath = "/var/lib/${cfg.stateDirectory}/logs/log_*.txt";
      tag = cfg.logsTag;
      inherit (cfg) relpServerHost relpServerPort;
    };
  };
}

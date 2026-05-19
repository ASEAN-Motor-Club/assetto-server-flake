{
  lib,
  config,
  ...
}:
with lib; let
  cfg = config;
  backendOptions = {
    enable = mkEnableOption "AssettoServer (Assetto Corsa freeroam server)";

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the required UDP port for the game server";
    };

    port = mkOption {
      type = types.port;
      default = 9600;
      description = "UDP game port";
    };

    serverVersion = mkOption {
      type = types.str;
      default = "v0.0.54";
      description = "AssettoServer release tag (github.com/compujuckel/AssettoServer)";
    };

    serverName = mkOption {
      type = types.str;
      default = "AssettoServer";
      description = "Server name shown in the server list";
    };

    serverDescription = mkOption {
      type = types.str;
      default = "";
      description = "Server description";
    };

    maxPlayers = mkOption {
      type = types.ints.positive;
      default = 10;
      description = "Maximum number of players";
    };

    track = mkOption {
      type = types.str;
      example = "shuto_revival_project_beta";
      description = "Track folder name (must exist under content/tracks/ in the content directory)";
    };

    trackLayout = mkOption {
      type = types.str;
      default = "";
      description = "Track layout name (leave empty for default)";
    };

    cars = mkOption {
      type = types.listOf types.str;
      example = ["ks_toyota_gt86" "ks_mazda_miata"];
      description = "List of car model folder names available on the server";
    };

    carSkins = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = {
        ks_toyota_gt86 = "0_86_red";
      };
      description = "Per-car skin override (attrset of car model to skin name)";
    };

    welcomeMessage = mkOption {
      type = types.str;
      default = "";
      description = "Welcome message shown to players on join";
    };

    admins = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["76561198378447512"];
      description = "List of admin SteamID64 values";
    };

    password = mkOption {
      type = types.str;
      default = "";
      description = "Server password (empty for no password)";
    };

    isPrivate = mkOption {
      type = types.bool;
      default = true;
      description = "Hide from the public server list";
    };

    enableAi = mkEnableOption "AI traffic";

    aiTrafficSlots = mkOption {
      type = types.ints.unsigned;
      default = 0;
      description = ''
        Number of AI traffic car slots to add to the entry list.
        Only used when enableAi is true. These slots are added after player slots
        and use AI=auto. For SRP, ~170 is typical.
      '';
    };

    aiConfig = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        AI configuration overrides merged into extra_cfg.yml AiParams.
        Example: { AiAutoFillCount = 170; AiForceField = true; }
      '';
    };

    extraCfg = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        extra_cfg.yml overrides (merged with defaults using recursiveUpdate).
        See https://assettoserver.org/docs/reference/extra-cfg-yml for options.
      '';
    };

    cspExtraOptions = mkOption {
      type = types.str;
      default = "";
      description = "Raw csp_extra_options.ini content (placed in cfg/ as-is)";
    };

    cspMinVersion = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "2584";
      description = ''
        Minimum CSP (Custom Shaders Patch) version ID required to join.
        Set to null to disable the check. Version 2584 = CSP 0.2.3+ (pinned chat).
      '';
    };

    contentHostPath = mkOption {
      type = types.str;
      default = "/var/lib/ac-content";
      description = ''
        Host path containing the AC content directory.
        Expected structure: <contentHostPath>/content/tracks/ and <contentHostPath>/content/cars/
      '';
    };

    stateDirectory = mkOption {
      type = types.str;
      default = "ac-server";
      description = "State directory name (under /var/lib)";
    };

    user = mkOption {
      type = types.str;
      default = "ac";
      description = "OS user for the service";
    };

    group = mkOption {
      type = types.str;
      default = "ac";
      description = "OS group for the service";
    };

    restartSchedule = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "*-*-* 09:30:00";
      description = "systemd OnCalendar restart schedule (null to disable)";
    };

    enableLogStreaming = mkEnableOption "rsyslog log forwarding";
    logsTag = mkOption {
      type = types.str;
      default = "ac";
      description = "Tag for forwarded log lines";
    };
    relpServerHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "RELP target host";
    };
    relpServerPort = mkOption {
      type = types.int;
      default = 2514;
      description = "RELP target port";
    };

    discordWebhookEnvironmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Env file with DISCORD_ERRORS_WEBHOOK for crash notifications";
    };

    cpuAffinity = mkOption {
      type = types.str;
      default = "6 7";
      description = "CPU cores to pin to (must NOT overlap Motor Town 0-3 or BeamMP 4-5)";
    };
    memoryMax = mkOption {
      type = types.str;
      default = "1G";
      description = "Hard memory cap (systemd unit syntax)";
    };
    memoryHigh = mkOption {
      type = types.str;
      default = "768M";
      description = "Memory pressure watermark (systemd unit syntax)";
    };
    cpuQuota = mkOption {
      type = types.str;
      default = "200%";
      description = "CPU quota cap (200% = 2 full cores)";
    };

    nice = mkOption {
      type = types.int;
      default = 0;
      description = "Process nice value";
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Extra environment variables for the server process";
    };
  };
in {
  options = backendOptions;
}

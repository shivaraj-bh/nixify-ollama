{ pkgs, lib, config, ... }:
let
  inherit (lib) types;
  cfg = config.services.ollama;
in
{
  options.services.ollama = {
    enable = lib.mkEnableOption "Enable the Ollama service";
    package = lib.mkOption {
      type = types.package;
      default = pkgs.ollama;
      description = "The Ollama package to use";
    };
    port = lib.mkOption {
      type = types.int;
      default = 11434;
      description = "The port on which the Ollama service's REST API will listen";
    };
    host = lib.mkOption {
      type = types.str;
      default = "localhost";
      description = "The host on which the Ollama service's REST API will listen";
    };
    dataDir = lib.mkOption {
      type = types.str;
      default = "./data/ollama";
      description = ''
        The directory containing the Ollama models.
        Sets the `OLLAMA_MODELS` environment variable.
      '';
    };
    keepAlive = lib.mkOption {
      type = types.str;
      default = "5m";
      description = ''
        The duration that models stay loaded in memory.
        Sets the `OLLAMA_KEEP_ALIVE` environment variable.

        Note: Use a duration string like "5m" for 5 minutes. Or "70" for 70 seconds.
      '';
      example = "70";
    };
    models = lib.mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        The models to load post start.
        Search for models of your choice from: https://ollama.com/library
      '';
    };

    defaultEnvs = lib.mkOption {
      type = types.attrsOf types.str;
      internal = true;
      readOnly = true;
      default = {
        OLLAMA_MODELS = cfg.dataDir;
        OLLAMA_HOST = "${cfg.host}:${toString cfg.port}";
        OLLAMA_KEEP_ALIVE = cfg.keepAlive;
      };
      description = ''
        Default environment variables passed to the `ollama-server` process.
      '';
    };

    extraEnvs = lib.mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        OLLAMA_DEBUG = "1";
      };
      description = ''
        Extra environment variables passed to the `ollama-server` process. This is prioritized over `defaultEnvs`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    settings.processes = {
      "ollama" =
        let
          startScript = pkgs.writeShellApplication {
            name = "ollama-server";
            text = ''
              if [ ! -d ${cfg.dataDir} ]; then
                echo "Creating directory ${cfg.dataDir}"
                mkdir -p ${cfg.dataDir}
              fi

              ${lib.getExe cfg.package} serve
            '';
          };
        in
        {
          command = startScript;
          environment = lib.recursiveUpdate cfg.defaultEnvs cfg.extraEnvs;
          readiness_probe = {
            http_get = {
              host = cfg.host;
              port = cfg.port;
            };
            initial_delay_seconds = 2;
            period_seconds = 10;
            timeout_seconds = 4;
            success_threshold = 1;
            failure_threshold = 5;
          };
          namespace = "ollama";
          availability.restart = "on_failure";
        };
      "ollama-models" = {
        command = pkgs.writeShellApplication {
          name = "ollama-models";
          text = ''
            set -x
            OLLAMA_HOST=${cfg.host}:${toString cfg.port}
            export OLLAMA_HOST
            models="${lib.concatStringsSep " " cfg.models}"
            for model in $models
            do
              ${lib.getExe cfg.package} pull "$model"
            done
          '';
        };
        namespace = "ollama";
        depends_on."ollama".condition = "process_healthy";
      };
    };
  };
}

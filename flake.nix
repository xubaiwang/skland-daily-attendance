{
  description = "基于 Node.js 和 Github Actions 实现的森空岛自动签到";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      flake-utils,
      nixpkgs,
      ...
    }:
    # 所有系统
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      with pkgs;
      rec {
        # 打包 TypeScript 文件作为库
        packages.lib = stdenvNoCC.mkDerivation (finalAttrs: {
          pname = "skland-daily-attendance";
          version = "1.0.0";

          src = ./.;

          pnpmDeps = pnpm_9.fetchDeps {
            inherit (finalAttrs) pname version src;
            hash = "sha256-ydd3G6XGS5ua2QQt0mN+StKTndzDtxgHHis3wU+LhJ0=";
          };
          nativeBuildInputs = [
            nodejs
            pnpm_9.configHook
          ];

          installPhase = ''
            mkdir -p $out
            cp -r main.ts src/ node_modules/ package.json pnpm-lock.yaml tsconfig.json . $out
          '';
        });

        # 包装为 Bash 脚本
        packages.script = pkgs.writeShellApplication {
          name = "skland-daily-attendance";
          runtimeInputs = [ nodejs ];
          text = ''
            npm run -C ${packages.lib} attendance
          '';
        };

        # 默认包为 Bash 脚本
        packages.default = packages.script;

        # 默认开发环境
        devShells.default = mkShell {
          buildInputs = [
            nodejs
            pnpm_9
          ];
        };
      }
    )
    // flake-utils.lib.eachDefaultSystemPassThrough (system: {
      # Home Manager 模块
      homeModules.default =
        {
          config,
          pkgs,
          lib,
          ...
        }:
        let
          cfg = config.services.skland-daily-attendance;
        in
        {
          # 配置类型定义
          options = {
            services.skland-daily-attendance = {
              # 是否启用
              enable = lib.mkEnableOption "skland-daily-attendance";

              # 定时时间
              onCalendar = lib.mkOption {
                type = lib.types.str;
                default = "04:00";
                example = "daily";
                description = ''
                  运行时间，默认每天 4:00 运行。

                  具体配置请参阅 {manpage}`systemd.time(7)`.
                '';
              };

              # 令牌
              tokens = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = ''
                  森空岛 token 列表。

                  登录森空岛网页版后，打开 https://web-api.skland.com/account/info/hg 记下 content 字段的值。

                  此处为列表类型，会自动拼接为环境变量。
                '';
              };

              # 随机延时
              randomizedDelaySec = lib.mkOption {
                type = lib.types.str;
                default = "20min";
                description = ''
                  运行时随机延时，避免被识别。
                '';
              };

              # 立即执行
              persistent = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = ''
                  服务启动后是否立即执行。
                '';
              };

              # 使用的包
              package = lib.mkOption {
                type = lib.types.package;
                default = self.outputs.packages.${system}.default;
              };

              # Server 酱
              serverchanSendkey = lib.mkOption {
                default = null;
                type = lib.types.nullOr lib.types.str;
                description = "Server 酱推送密钥，可选";
              };

              # Bark 推送
              barkUrl = lib.mkOption {
                default = null;
                type = lib.types.nullOr lib.types.str;
                description = "Bark 推送地址，可选";
              };
            };
          };

          # 配置实现
          config = lib.mkIf cfg.enable {
            # 服务
            systemd.user.services.skland-daily-attendance = {
              Unit = {
                Description = "基于 Node.js 和 Github Actions 实现的森空岛自动签到";
              };
              Install = {
                WantedBy = [ "default.target" ];
              };
              Service = {
                ExecStart = "${cfg.package}/bin/skland-daily-attendance";
                Environment =
                  let
                    maybeEnv = n: v: lib.optionals (v != null) [ "${n}=${v}" ];
                  in
                  [
                    "SKLAND_TOKEN=${lib.concatStringsSep "," cfg.tokens}"
                  ]
                  ++ maybeEnv "SERVERCHAN_SENDKEY" cfg.serverchanSendkey
                  ++ maybeEnv "BARK_URL" cfg.barkUrl;
              };
            };

            # 定时器
            systemd.user.timers.skland-daily-attendance = {
              Unit = {
                Description = "每日运行森空岛签到";
              };
              Timer = {
                OnCalendar = cfg.onCalendar;
                Persistent = cfg.persistent;
                RandomizedDelaySec = "20min";
              };
              Install = {
                WantedBy = [ "timers.target" ];
              };
            };
          };
        };
    });
}

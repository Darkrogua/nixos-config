{ pkgs, ... }:
let
  gruvbox-material-icon-theme-src = pkgs.fetchFromGitHub {
    owner = "Jonathan-Harty";
    repo = "vscode-material-icon-theme";
    rev = "9f7f877a5501a0cbd722754264a76dd936cd00ca";
    hash = "sha256-moGqAM0Yc/kvJFQeQNrvov7/4iJwFosa8Xvt37zC+cw=";
  };

  jonathanharty.gruvbox-material-icon-theme = pkgs.vscode-utils.buildVscodeExtension {
    pname = "JonathanHarty-gruvbox-material-icon-theme";
    version = "1.1.5";
    vscodeExtPublisher = "JonathanHarty";
    vscodeExtName = "gruvbox-material-icon-theme";
    vscodeExtUniqueId = "JonathanHarty.gruvbox-material-icon-theme";

    src = gruvbox-material-icon-theme-src;

    nativeBuildInputs = [
      pkgs.nodejs
      pkgs.npmHooks.npmConfigHook
    ];

    npmDeps = pkgs.fetchNpmDeps {
      pname = "gruvbox-material-icon-theme";
      version = "1.1.5";
      src = gruvbox-material-icon-theme-src;
      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };

    env.PUPPETEER_SKIP_DOWNLOAD = "1";

    buildPhase = ''
      runHook preBuild
      npm run build
      runHook postBuild
    '';
  };
in
{
  programs.vscode.profiles.default = {
    extensions = with pkgs.vscode-extensions; [
      ## Languages
      jnoortheen.nix-ide
      arrterian.nix-env-selector
      # ms-python.python
      llvm-vs-code-extensions.vscode-clangd
      ziglang.vscode-zig
      tamasfe.even-better-toml
      golang.go

      ## Color scheme
      jdinhlife.gruvbox
      jonathanharty.gruvbox-material-icon-theme
    ];
  };
}

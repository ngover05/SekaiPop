# SekaiPop on distros without pacman (Debian, Ubuntu, Linux Mint...).
#
# Their own repositories are too old for the shell (Hyprland 0.55+, Quickshell, Qt 6.7+), so
# install-deps-debian.sh takes those, and the Wayland tools that go with them, from nixpkgs.
# The distro keeps everything system-level (services, PipeWire, NetworkManager, polkitd, fonts).
#
#   sekaipop-core        what the shell cannot start without
#   sekaipop-full        core + the feature tools (the default)
#   sekaipop-everything  full + the optional extras (--with-optional)
#   system               root-owned profile, linked to /run/opengl-driver: the GPU drivers that
#                        Nix programs load, and the Hyprland screen-sharing portal
#
# Nix programs and these drivers have to come from the same nixpkgs, so the installer always
# builds both from this flake in one run. Don't upgrade one without the other.
{
  description = "Hyprland, Quickshell and the Wayland tools SekaiPop needs, for non-Arch distros";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in {
      packages = forAll (pkgs:
        let
          qt = pkgs.qt6;
          qml = p: "${p}/${qt.qtbase.qtQmlPrefix}";
          plugins = p: "${p}/${qt.qtbase.qtPluginPrefix}";

          # nixpkgs' quickshell only carries the Qt modules it needs itself. The shell also
          # imports QtMultimedia (video wallpapers, sounds) and reads webp wallpapers.
          # NIXPKGS_QT6_QML_IMPORT_PATH is read by Nix's Qt only, so it can't confuse the
          # distro's own (older) Qt apps that the shell launches.
          quickshell = pkgs.symlinkJoin {
            name = "sekaipop-quickshell-${pkgs.quickshell.version}";
            paths = [ pkgs.quickshell ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/quickshell \
                --prefix NIXPKGS_QT6_QML_IMPORT_PATH : ${qml qt.qtmultimedia} \
                --prefix QT_PLUGIN_PATH : ${plugins qt.qtmultimedia}:${plugins qt.qtimageformats}
              rm -f $out/bin/qs
              ln -s quickshell $out/bin/qs
            '';
          };

          # check-deps.sh can't ask a qmake for these: there is none on PATH.
          qtInfo = pkgs.writeTextDir "share/sekaipop/nix-qt.env" ''
            SEKAIPOP_QT_VERSION=${qt.qtbase.version}
            SEKAIPOP_QML_DIRS=${pkgs.lib.concatMapStringsSep ":" qml [ pkgs.quickshell qt.qtdeclarative qt.qtmultimedia qt.qtwayland qt.qtsvg ]}
            SEKAIPOP_QT_PLUGIN_DIRS=${pkgs.lib.concatMapStringsSep ":" plugins [ qt.qtbase qt.qtsvg qt.qtimageformats qt.qtwayland qt.qtmultimedia ]}
          '';

          core = with pkgs; [
            hyprland xwayland quickshell qtInfo
            qt.qtshadertools   # qsb, for shaders/compile-shaders.sh
            wl-clipboard
            playerctl hypridle # the preconfigured keybinds and idle lock
            material-symbols
            glibcLocales       # Nix's glibc can't read the distro's locale archive
          ];
          features = with pkgs; [
            matugen adw-gtk3 bibata-cursors nerd-fonts.jetbrains-mono
            cava easyeffects
            grim slurp swappy wf-recorder imagemagick hyprpicker
            cliphist wtype
            hyprsunset
          ];
          optional = with pkgs; [ mpvpaper nwg-displays songrec ];

          env = name: paths: pkgs.buildEnv {
            inherit name paths;
            ignoreCollisions = true;
          };
        in {
          sekaipop-core = env "sekaipop-core" core;
          sekaipop-full = env "sekaipop-full" (core ++ features);
          sekaipop-everything = env "sekaipop-everything" (core ++ features ++ optional);
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.sekaipop-full;

          # What NixOS puts at /run/opengl-driver (Mesa: GL, EGL, GBM, Vulkan, VA-API), plus
          # the portal, whose files the installer links into /usr/share for the distro's
          # xdg-desktop-portal to find.
          # hyprland-portals.conf comes with Hyprland itself, not with the portal.
          system = env "sekaipop-system" [
            pkgs.mesa
            pkgs.xdg-desktop-portal-hyprland
            (pkgs.runCommand "hyprland-portals-conf" { } ''
              install -Dm644 ${pkgs.hyprland}/share/xdg-desktop-portal/hyprland-portals.conf \
                $out/share/xdg-desktop-portal/hyprland-portals.conf
            '')
          ];
        });
    };
}

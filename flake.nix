{
  description = "Ripcord: a small, resident launcher for Apple silicon Macs";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # Apple silicon macOS is the only target.
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib;
      # Info.plist is the one place the version lives.
      version = lib.head (
        builtins.match ".*<key>CFBundleShortVersionString</key>[[:space:]]*<string>([^<]+)</string>.*" (
          builtins.readFile ./Resources/Info.plist
        )
      );
    in
    {
      packages.${system}.default = pkgs.stdenvNoCC.mkDerivation {
        pname = "ripcord";
        inherit version;
        src = lib.cleanSource self;

        # Built with the host's Xcode, not nixpkgs' Swift: SwiftUI's @State is a macro whose
        # plugin ships only with Xcode. That needs Xcode installed and a Nix sandbox that lets
        # the build reach it (sandbox = false or relaxed, the default on macOS).
        __noChroot = true;
        dontConfigure = true;
        # Fixup would rewrite the signed binary.
        dontFixup = true;

        buildPhase = ''
          runHook preBuild
          export HOME=$TMPDIR PATH=/usr/bin:/bin:$PATH
          SWIFT_BUILD_FLAGS=--disable-sandbox sh scripts/build-app.sh
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out/Applications $out/bin
          cp -R build/Ripcord.app $out/Applications/
          ln -s $out/Applications/Ripcord.app/Contents/MacOS/ripcord-cli $out/bin/ripcord
          runHook postInstall
        '';

        meta = {
          description = "A small, resident launcher for Apple silicon Macs";
          homepage = "https://github.com/meltin/ripcord";
          license = lib.licenses.mit;
          platforms = [ system ];
        };
      };
    };
}

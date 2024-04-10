{ stdenv, lib, documentation-highlighter, nmd, revision, home-manager-options
, nixos-render-docs }:
let outputPath = "share/doc/home-manager";
in stdenv.mkDerivation {
  name = "nixpkgs-manual";

  nativeBuildInputs = [ nixos-render-docs ];

  src = ./manual;

  buildPhase = ''
    mkdir -p out/media

    mkdir -p out/highlightjs
    cp -t out/highlightjs \
      ${documentation-highlighter}/highlight.pack.js \
      ${documentation-highlighter}/LICENSE \
      ${documentation-highlighter}/mono-blue.css \
      ${documentation-highlighter}/loader.js

    substituteInPlace ./options.md \
      --replace \
        '@OPTIONS_JSON@' \
        ${home-manager-options.home-manager}/share/doc/nixos/options.json

    substituteInPlace ./nixos-options.md \
      --replace \
        '@OPTIONS_JSON@' \
        ${home-manager-options.nixos}/share/doc/nixos/options.json

    substituteInPlace ./nix-darwin-options.md \
      --replace \
        '@OPTIONS_JSON@' \
        ${home-manager-options.nix-darwin}/share/doc/nixos/options.json

    nixos-render-docs manual html \
      --manpage-urls ./manpage-urls.json \
      --revision ${lib.trivial.revisionWithDefault revision} \
      --stylesheet ${nmd}/static/style.css \
      --stylesheet ${nmd}/static/highlightjs/tomorrow-night.min.css \
      --script ${nmd}/static/highlightjs/highlight.min.js \
      --script ${nmd}/static/highlightjs/highlight.load.js \
      --toc-depth 1 \
      --section-toc-depth 1 \
      manual.md \
      out/index.html
  '';

  installPhase = ''
    dest="$out/${outputPath}"
    mkdir -p "$(dirname "$dest")"
    mv out "$dest"

    mkdir -p $out/nix-support/
    echo "doc manual $dest index.html" >> $out/nix-support/hydra-build-products
  '';
}

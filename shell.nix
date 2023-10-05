let
  unstable = import (fetchTarball https://nixos.org/channels/nixos-unstable/nixexprs.tar.xz) { };
in
{ nixpkgs ? import <nixpkgs> {} }:
with nixpkgs; mkShell {
  buildInputs = with pkgs; [
    unstable.zig
    unstable.zls
    cmark # So that I can get man cmake.3
    ];
}

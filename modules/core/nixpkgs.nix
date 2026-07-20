{ pkgs, inputs, ... }:
{
  nixpkgs = {
    overlays = [
      (
        final: prev:
        (import ../../pkgs {
          inherit inputs;
          inherit pkgs;
        })
      )
      inputs.nur.overlays.default
    ];
  };
}

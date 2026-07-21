{ lib, ... }:

let
  inherit (lib.gvariant) mkUint32;
in

{
  # Linux counterpart of what `system.defaults` did on macOS.
  # Standalone home-manager can only reach the user's dconf database, so these
  # are desktop-session settings, not system settings.
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
    };

    # macOS KeyRepeat = 2 and InitialKeyRepeat = 15, in 15 ms units.
    "org/gnome/desktop/peripherals/keyboard" = {
      repeat = true;
      repeat-interval = mkUint32 30;
      delay = mkUint32 225;
    };

    "org/gnome/desktop/peripherals/touchpad" = {
      tap-to-click = true;
      natural-scroll = true;
    };

    # macOS finder.FXPreferredViewStyle = "Nlsv".
    "org/gnome/nautilus/preferences".default-folder-viewer = "list-view";

    # macOS finder.CreateDesktop = false: GNOME has no desktop icons by default,
    # so nothing to disable here.
  };

  # No equivalents on GNOME, deliberately dropped from the macOS config:
  # - dock.autohide       -> stock GNOME has no always-on dock (dash lives in the overview)
  # - _HIHideMenuBar      -> the GNOME top bar is not hideable without an extension
  # - AppleShowAllExtensions -> Nautilus always shows file extensions
}

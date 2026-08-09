{ lib, profile, ... }:

{
  # XSettings and xfwm4 are X11-only. Generic GTK files remain user-owned.
  xfconf.settings = {
    thunar = {
      "last-view" = "ThunarDetailsView";
      "last-show-hidden" = true;
    };

    xfce4-desktop = {
      "desktop-icons/style" = 0;
    };
  } // lib.optionalAttrs (profile.displayServer != "wayland") {
    xsettings."Net/ThemeName" = "Adwaita-dark";
    xfwm4 = {
      "general/cycle_workspaces" = false;
      "general/scroll_workspaces" = false;
      "general/wrap_windows" = false;
      "general/wrap_workspaces" = false;
    };
  };
}

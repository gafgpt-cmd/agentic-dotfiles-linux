{
  # Install tools and privacy controls; adopt WezTerm and its Neovim launcher.
  # Supported desktop values: "none", "gnome", "xfce", "kde".
  desktop = "none";
  # "auto" leaves toolkit detection alone; explicit values select terminal backend.
  displayServer = "auto"; # "auto", "x11", "wayland"

  manageShell = false;
  manageNvim = false;
  manageWezterm = true;
  manageHerdr = false;
  managePiResources = false;
  manageClaudeSettings = false;
  manageAgentInstructions = false;
}

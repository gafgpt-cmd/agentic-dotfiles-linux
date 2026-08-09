{
  # Safe first switch: install tools and privacy controls without adopting live configs.
  # Supported desktop values: "none", "gnome", "xfce", "kde".
  desktop = "none";
  # "auto" leaves toolkit detection alone; explicit values select terminal backend.
  displayServer = "auto"; # "auto", "x11", "wayland"

  manageShell = false;
  manageNvim = false;
  manageWezterm = false;
  manageHerdr = false;
  managePiResources = false;
  manageClaudeSettings = false;
  manageAgentInstructions = false;
}

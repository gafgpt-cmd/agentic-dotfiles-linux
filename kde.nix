{
  # Plasma Manager edits only the keys below. It never resets or replaces the
  # rest of an existing KDE setup because overrideConfig remains false.
  programs.plasma = {
    enable = true;
    overrideConfig = false;
    workspace = {
      lookAndFeel = "org.kde.breezedark.desktop";
      clickItemTo = "select";
    };
  };
}

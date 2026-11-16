from pathlib import Path

app = Path(defines["app"])
files = [str(app)]
symlinks = {"Applications": "/Applications"}
icon_locations = {app.name: (185, 192), "Applications": (487, 192)}
background = defines["background"]
badge_icon = str(app / "Contents/Resources/Yoru.icns")
window_rect = ((120, 160), (672, 426))
icon_size = 96
text_size = 13
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_pathbar = False
format = "ULFO"

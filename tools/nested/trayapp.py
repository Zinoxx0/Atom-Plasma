#!/usr/bin/env python3
"""A pretend app with a tray icon, for the nested tests: trayapp.py NAME [--window]. The tray icon's id and
the window's app id are both NAME; a click on the icon prints "NAME activated" (that's the app being asked
to open itself: the shell does that only when the app has no window)."""
import sys

from PyQt6.QtGui import QColor, QGuiApplication, QIcon, QPixmap
from PyQt6.QtWidgets import QApplication, QLabel, QSystemTrayIcon

name = sys.argv[1]
QGuiApplication.setDesktopFileName(name)
app = QApplication(sys.argv)
app.setApplicationName(name)
app.setQuitOnLastWindowClosed(False)

pix = QPixmap(64, 64)
pix.fill(QColor({"trayalpha": "#e0556b", "traybeta": "#55b0e0", "traygamma": "#8be055"}.get(name, "#cccccc")))
tray = QSystemTrayIcon(QIcon(pix))
tray.setToolTip(name)
tray.activated.connect(lambda reason: print(name, "activated", reason.name, flush=True))
tray.show()

if "--window" in sys.argv:
    win = QLabel(name)
    win.setWindowTitle(name)
    win.resize(480, 300)
    win.show()

print(name, "up, tray", QSystemTrayIcon.isSystemTrayAvailable(), flush=True)
sys.exit(app.exec())

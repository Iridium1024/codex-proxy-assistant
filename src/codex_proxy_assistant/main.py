from __future__ import annotations

import sys

from PyQt5.QtWidgets import QApplication

from .main_window import MainWindow
from .theme import app_stylesheet


def main() -> int:
    app = QApplication(sys.argv)
    app.setApplicationName("Codex Proxy Assistant")
    app.setStyleSheet(app_stylesheet())
    window = MainWindow()
    window.show()
    return app.exec_()


if __name__ == "__main__":
    raise SystemExit(main())

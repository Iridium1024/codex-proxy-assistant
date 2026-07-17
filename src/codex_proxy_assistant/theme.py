from dataclasses import dataclass
from pathlib import Path
import sys


@dataclass(frozen=True)
class Theme:
    font_family: str = "'Microsoft YaHei UI', 'Segoe UI', sans-serif"
    primary: str = "#1f6feb"
    success: str = "#157f3b"
    danger: str = "#d9534f"
    text: str = "#27313d"
    muted: str = "#667085"
    background: str = "#f7f9fc"
    panel: str = "#fbfcfe"
    border: str = "#d6dde8"
    radius: int = 8


THEME = Theme()


def asset_path(name: str) -> str:
    if getattr(sys, "frozen", False):
        root = Path(getattr(sys, "_MEIPASS")).resolve()
    else:
        root = Path(__file__).resolve().parents[2]
    return (root / "assets" / name).resolve().as_posix()


def app_stylesheet() -> str:
    t = THEME
    arrow = asset_path("chevron-down.svg")
    disabled_arrow = asset_path("chevron-down-disabled.svg")
    return f"""
        QWidget {{
            font-family: {t.font_family};
            font-size: 13px;
            color: {t.text};
        }}
        QWidget#appRoot, QMainWindow {{
            background-color: {t.background};
        }}
        QLabel[role="caption"] {{
            font-size: 12px;
            color: {t.muted};
        }}
        QLabel[role="ok"] {{
            color: {t.success};
            font-size: 12px;
        }}
        QLabel[role="warn"] {{
            color: #a15c00;
            font-size: 12px;
        }}
        QLabel[role="error"] {{
            color: {t.danger};
            font-size: 12px;
        }}
        QLabel[placement="inline"] {{
            font-size: 13px;
        }}
        QGroupBox {{
            border: 1px solid {t.border};
            border-radius: {t.radius}px;
            margin-top: 0;
            padding: 0;
            background-color: {t.panel};
            font-weight: 400;
        }}
        QLineEdit, QComboBox {{
            border: 1px solid #cbd5e1;
            border-radius: {t.radius}px;
            background-color: {t.background};
            selection-background-color: {t.primary};
        }}
        QLineEdit {{
            padding: 0;
        }}
        QFrame#pathComboFrame {{
            border: 1px solid #cbd5e1;
            border-radius: {t.radius}px;
            background-color: {t.background};
        }}
        QFrame#pathComboFrame:hover {{
            border-color: #c2cad7;
            background-color: #f5f7fa;
        }}
        QLineEdit:hover, QComboBox:hover {{
            border-color: #c2cad7;
            background-color: #f5f7fa;
        }}
        QLineEdit:focus, QComboBox:focus, QComboBox:on {{
            border-color: {t.primary};
            background-color: {t.background};
        }}
        QComboBox#pathCombo,
        QComboBox#pathCombo:hover,
        QComboBox#pathCombo:focus,
        QComboBox#pathCombo:on {{
            border: none;
            border-radius: 7px;
            background-color: transparent;
        }}
        QComboBox {{
            padding: 0 38px 0 9px;
        }}
        QComboBox:editable {{
            padding: 0 38px 0 0;
        }}
        QComboBox QLineEdit {{
            border: none;
            border-radius: 0;
            padding: 0;
            min-height: 0;
            background-color: transparent;
        }}
        QComboBox QLineEdit:hover,
        QComboBox QLineEdit:focus {{
            border: none;
            background-color: transparent;
        }}
        QComboBox::drop-down {{
            subcontrol-origin: padding;
            subcontrol-position: top right;
            width: 30px;
            border-left: 1px solid {t.border};
            border-top-right-radius: 7px;
            border-bottom-right-radius: 7px;
            background-color: #f2f5f9;
        }}
        QComboBox::drop-down:hover,
        QComboBox::drop-down:on {{
            background-color: #eaf2ff;
            border-left-color: #c7d5e8;
        }}
        QComboBox::down-arrow {{
            image: url("{arrow}");
            width: 12px;
            height: 8px;
        }}
        QComboBox::down-arrow:on {{
            top: 1px;
        }}
        QComboBox:disabled {{
            color: #a9b0ba;
            border-color: #e3e7ed;
            background-color: #f2f5f9;
        }}
        QComboBox::drop-down:disabled {{
            border-left-color: #e3e7ed;
            background-color: #eef2f6;
        }}
        QComboBox::down-arrow:disabled {{
            image: url("{disabled_arrow}");
        }}
        QComboBox QAbstractItemView {{
            color: {t.text};
            border: 1px solid #cbd5e1;
            border-radius: {t.radius}px;
            padding: 5px;
            background-color: white;
            selection-color: {t.text};
            selection-background-color: #eaf2ff;
            outline: 0;
        }}
        QComboBox QAbstractItemView::item {{
            min-height: 32px;
            padding: 0 9px;
            border-radius: 5px;
        }}
        QComboBox QAbstractItemView::item:hover {{
            background-color: #f1f5fb;
        }}
        QComboBox QAbstractItemView::item:selected {{
            color: #174ea6;
            background-color: #eaf2ff;
        }}
        QLineEdit:read-only {{
            color: #4f5b6b;
            background-color: #f2f5f9;
        }}
        QPushButton {{
            background-color: transparent;
            color: {t.text};
            border: 1px solid {t.border};
            border-radius: {t.radius}px;
            padding: 0 12px;
        }}
        QPushButton:hover {{
            background-color: #f1f4f8;
            border-color: {t.primary};
        }}
        QPushButton:pressed {{
            background-color: #e9eef5;
        }}
        QPushButton:disabled {{
            color: #a9b0ba;
            border-color: #e3e7ed;
            background-color: transparent;
        }}
        QProgressBar {{
            border: 1px solid {t.border};
            border-radius: {t.radius}px;
            text-align: center;
            background-color: #eef2f7;
            min-height: 16px;
        }}
        QProgressBar::chunk {{
            background-color: {t.primary};
            border-radius: {t.radius}px;
        }}
        QTextBrowser {{
            border: 1px solid {t.border};
            border-radius: {t.radius}px;
            padding: 8px;
            background-color: white;
            font-family: Consolas, 'Microsoft YaHei UI', monospace;
            font-size: 12px;
        }}
        QScrollBar:vertical {{
            width: 10px;
            background: transparent;
            margin: 2px;
        }}
        QScrollBar::handle:vertical {{
            min-height: 30px;
            background: #c7ced8;
            border-radius: 5px;
        }}
        QScrollBar::handle:vertical:hover {{ background: #aeb8c5; }}
        QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{ height: 0; }}
    """

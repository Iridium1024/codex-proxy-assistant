from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from PyQt5.QtCore import QPoint, Qt
from PyQt5.QtWidgets import QApplication, QMessageBox


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT / "src"))

from codex_proxy_assistant.main_window import (  # noqa: E402
    CONTROL_HEIGHT,
    FIELD_CONTENT_OFFSET,
    FIELD_TEXT_MARGIN,
    MainWindow,
)
from codex_proxy_assistant.theme import app_stylesheet, asset_path  # noqa: E402


class GuiSmokeTests(unittest.TestCase):
    def test_gui_modules_and_theme_load(self) -> None:
        stylesheet = app_stylesheet()
        self.assertIn("#1f6feb", stylesheet)
        self.assertIn("Microsoft YaHei UI", stylesheet)
        self.assertNotIn('QPushButton[role="primary"]', stylesheet)
        self.assertIn("QComboBox::drop-down", stylesheet)
        self.assertIn("QComboBox QAbstractItemView::item:selected", stylesheet)
        self.assertTrue(Path(asset_path("chevron-down.svg")).is_file())
        self.assertEqual(CONTROL_HEIGHT, 32)

    def test_minimum_window_layout_and_focus_are_stable(self) -> None:
        class QuietWindow(MainWindow):
            def auto_detect(self) -> None:
                pass

        app = QApplication.instance() or QApplication([])
        app.setStyleSheet(app_stylesheet())
        window = QuietWindow()
        window.show()
        app.processEvents()
        root = window.centralWidget()

        self.assertEqual(window.size(), window.minimumSize())

        def left(widget) -> int:
            return widget.mapTo(root, QPoint(0, 0)).x()

        def right(widget) -> int:
            return left(widget) + widget.width()

        self.assertLessEqual(right(window.codex_combo_frame), left(window.browse_button))
        self.assertEqual(left(window.log_title), left(window.auto_button))
        self.assertEqual(left(window.progress_bar), left(window.preview_button))
        self.assertEqual(right(window.progress_bar), right(window.apply_button))
        self.assertEqual(
            {
                window.codex_combo_frame.height(),
                window.proxy_edit.height(),
                window.config_path_edit.height(),
                window.snapshot_combo.height(),
                window.check_codex_button.height(),
                window.auto_button.height(),
            },
            {CONTROL_HEIGHT},
        )
        self.assertEqual(window.codex_combo.lineEdit().textMargins().left(), FIELD_TEXT_MARGIN)
        self.assertEqual(window.proxy_edit.textMargins().left(), FIELD_TEXT_MARGIN)
        self.assertEqual(window.config_path_edit.textMargins().left(), FIELD_TEXT_MARGIN)
        self.assertEqual(window.codex_status.contentsMargins().left(), FIELD_CONTENT_OFFSET)
        self.assertEqual(window.proxy_status.contentsMargins().left(), FIELD_CONTENT_OFFSET)
        self.assertEqual(window.config_state_label.height(), CONTROL_HEIGHT)
        self.assertTrue(window.config_state_label.alignment() & Qt.AlignVCenter)
        self.assertIsNone(window.apply_button.property("role"))
        self.assertIsNone(window.restore_button.property("role"))

        proxy_text_left = left(window.proxy_edit) + FIELD_CONTENT_OFFSET
        config_text_left = left(window.config_path_edit) + FIELD_CONTENT_OFFSET
        combo_text_left = (
            left(window.codex_combo)
            + window.codex_combo.lineEdit().geometry().x()
            + FIELD_TEXT_MARGIN
        )
        self.assertEqual(combo_text_left, proxy_text_left)
        self.assertEqual(config_text_left, proxy_text_left)
        self.assertEqual(
            left(window.codex_status) + window.codex_status.contentsMargins().left(),
            proxy_text_left,
        )
        self.assertEqual(
            left(window.proxy_status) + window.proxy_status.contentsMargins().left(),
            proxy_text_left,
        )

        combo_corner = window.codex_combo_frame.grab().toImage()
        proxy_corner = window.proxy_edit.grab().toImage()
        for y in (0, 1, 2, 3, 4, 27, 28, 29, 30, 31):
            for x in range(12):
                self.assertEqual(combo_corner.pixelColor(x, y), proxy_corner.pixelColor(x, y))

        window.snapshot_combo.addItem("test")
        self.assertEqual(window.snapshot_combo.view().sizeHintForRow(0), CONTROL_HEIGHT)

        window.codex_combo.setEditText("C:/codex.exe")
        window._refresh_button_state()
        self.assertTrue(window.apply_button.isEnabled())
        self.assertTrue(window.restore_button.isEnabled())

        window.check_codex_button.setFocus()
        app.processEvents()
        window._set_busy(True, "test")
        app.processEvents()
        self.assertIs(QApplication.focusWidget(), root)
        window._set_busy(False)
        app.processEvents()
        self.assertIs(QApplication.focusWidget(), window.check_codex_button)

        window.report = {
            "config": {"feature_state": "true"},
            "proxy": {"configured": True, "tcp_reachable": True},
        }
        with patch.object(QMessageBox, "information", return_value=QMessageBox.Ok) as information:
            window.apply_repair()
            self.assertEqual(information.call_args.args[1], "无需修改")
            window.restore_snapshot()
            self.assertEqual(information.call_args.args[1], "暂无快照")
        window.close()


if __name__ == "__main__":
    unittest.main()

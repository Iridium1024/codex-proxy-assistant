from __future__ import annotations

import html
from datetime import datetime
from typing import Any

from PyQt5.QtCore import QSize, QThreadPool, QTimer, Qt
from PyQt5.QtWidgets import (
    QApplication,
    QComboBox,
    QFileDialog,
    QFrame,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QProgressBar,
    QPushButton,
    QSizePolicy,
    QStyledItemDelegate,
    QTextBrowser,
    QVBoxLayout,
    QWidget,
)

from .backend import PowerShellBackend, launch_temporary_codex
from .workers import FunctionTask


CONTROL_HEIGHT = 32
FIELD_TEXT_MARGIN = 9
FIELD_CONTENT_OFFSET = FIELD_TEXT_MARGIN + 1


STATE_TEXT = {
    "true": "已启用",
    "false": "已禁用",
    "missing": "未配置",
    "invalid-duplicate-section": "配置异常：重复 [features]",
    "invalid-duplicate-key": "配置异常：重复配置项",
    "invalid-value": "配置异常：值无法识别",
}

RESULT_TEXT = {
    "pending": "待验证",
    "success": "成功",
    "rolled_back": "失败并已回滚",
}

BACKEND_TEXT = {
    "The persistent setting is already enabled; applying would make no change.": "持久代理设置已经启用，本次不会产生修改。",
    "The existing config has an unsafe or duplicate [features] value.": "现有配置包含无法安全处理或重复的 [features] 设置。",
    "No runnable Codex engine was found.": "没有找到可运行的 Codex 引擎。",
    "The selected Codex engine did not confirm respect_system_proxy support.": "所选 Codex 未确认支持 respect_system_proxy。",
    "Windows system proxy, PAC, or WPAD is not enabled.": "Windows 系统代理、PAC 或自动发现均未启用。",
    "The configured Windows proxy port is not reachable.": "Windows 当前代理端口不可达。",
    "The proxy entered in the UI is invalid or unreachable.": "输入的代理地址无效或端口不可达。",
    "The entered proxy differs from the Windows system proxy; persistent repair would not use it.": "输入地址与 Windows 系统代理不同，不能用于持久修复。",
    "Proxy URLs containing a user name or password are not accepted.": "不接受包含用户名或密码的代理地址。",
}


def localize_backend_text(value: Any) -> str:
    text = str(value)
    for source, translated in BACKEND_TEXT.items():
        text = text.replace(source, translated)
    return text


class ComboItemDelegate(QStyledItemDelegate):
    """Keep combo popup rows spacious and consistent across Windows styles."""

    def sizeHint(self, option, index) -> QSize:  # noqa: N802 - Qt API name.
        size = super().sizeHint(option, index)
        size.setHeight(CONTROL_HEIGHT)
        return size


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Codex 代理诊断与修复")
        self.setMinimumSize(820, 450)
        self.resize(self.minimumSize())
        self.backend = PowerShellBackend()
        self.thread_pool = QThreadPool.globalInstance()
        self.report: dict[str, Any] | None = None
        self.busy = False
        self._focus_before_busy: QPushButton | None = None
        self._build_ui()
        self._set_ready_state()
        QTimer.singleShot(0, lambda: self.root_widget.setFocus(Qt.OtherFocusReason))
        QTimer.singleShot(250, self.auto_detect)

    def _build_ui(self) -> None:
        root = QWidget()
        root.setObjectName("appRoot")
        root.setFocusPolicy(Qt.StrongFocus)
        self.root_widget = root
        self.setCentralWidget(root)
        layout = QVBoxLayout(root)
        layout.setContentsMargins(20, 16, 20, 18)
        layout.setSpacing(9)

        layout.addWidget(self._build_control_panel())

        feedback_row = QGridLayout()
        feedback_row.setContentsMargins(13, 0, 13, 0)
        feedback_row.setHorizontalSpacing(4)
        self.log_title = QLabel("运行日志")
        self.log_title.setStyleSheet("font-weight: 600; font-size: 14px;")
        self.log_title.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        self.progress_label = QLabel("就绪")
        self.progress_label.setProperty("role", "caption")
        self.progress_label.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 100)
        self.progress_bar.setValue(0)
        self.progress_bar.setFixedHeight(18)
        self.progress_bar.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
        feedback_row.addWidget(self.log_title, 0, 0)
        feedback_row.addWidget(self.progress_label, 0, 1)
        feedback_row.addWidget(self.progress_bar, 0, 2, 1, 2)
        for column in range(4):
            feedback_row.setColumnStretch(column, 1)
        layout.addLayout(feedback_row)

        self.log_view = QTextBrowser()
        self.log_view.setMinimumHeight(90)
        layout.addWidget(self.log_view, 1)

    def _build_control_panel(self) -> QGroupBox:
        group = QGroupBox()
        grid = QGridLayout(group)
        grid.setContentsMargins(12, 10, 12, 10)
        grid.setHorizontalSpacing(8)
        grid.setVerticalSpacing(5)

        grid.addWidget(QLabel("Codex 路径："), 0, 0)
        self.codex_combo_frame = QFrame()
        self.codex_combo_frame.setObjectName("pathComboFrame")
        self.codex_combo_frame.setFixedHeight(CONTROL_HEIGHT)
        self.codex_combo_frame.setMinimumWidth(0)
        self.codex_combo_frame.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Fixed)
        combo_frame_layout = QHBoxLayout(self.codex_combo_frame)
        combo_frame_layout.setContentsMargins(0, 0, 0, 0)
        combo_frame_layout.setSpacing(0)

        self.codex_combo = QComboBox()
        self.codex_combo.setObjectName("pathCombo")
        self.codex_combo.setEditable(True)
        self.codex_combo.setInsertPolicy(QComboBox.NoInsert)
        self.codex_combo.lineEdit().setTextMargins(FIELD_TEXT_MARGIN, 0, FIELD_TEXT_MARGIN, 0)
        self.codex_combo.setSizeAdjustPolicy(QComboBox.AdjustToMinimumContentsLengthWithIcon)
        self.codex_combo.setMinimumContentsLength(10)
        self.codex_combo.setMinimumWidth(0)
        self.codex_combo.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Expanding)
        self.codex_combo.setMaxVisibleItems(7)
        self.codex_combo.setItemDelegate(ComboItemDelegate(self.codex_combo))
        self.codex_combo.view().setTextElideMode(Qt.ElideMiddle)
        combo_frame_layout.addWidget(self.codex_combo)
        grid.addWidget(self.codex_combo_frame, 0, 1)
        self.browse_button = QPushButton("...")
        self.browse_button.setFixedSize(44, CONTROL_HEIGHT)
        self.browse_button.setToolTip("选择 Codex 可执行文件")
        self.browse_button.clicked.connect(self.browse_codex)
        grid.addWidget(self.browse_button, 0, 2)
        self.check_codex_button = QPushButton("检测路径")
        self.check_codex_button.setFixedHeight(CONTROL_HEIGHT)
        self.check_codex_button.clicked.connect(self.check_codex)
        grid.addWidget(self.check_codex_button, 0, 3)
        self.codex_status = QLabel("尚未检测")
        self.codex_status.setProperty("role", "caption")
        self.codex_status.setContentsMargins(FIELD_CONTENT_OFFSET, 0, 0, 0)
        grid.addWidget(self.codex_status, 1, 1, 1, 3)

        grid.addWidget(QLabel("系统代理："), 2, 0)
        self.proxy_edit = QLineEdit()
        self.proxy_edit.setPlaceholderText("例如：http://127.0.0.1:7897")
        self.proxy_edit.setTextMargins(FIELD_TEXT_MARGIN, 0, FIELD_TEXT_MARGIN, 0)
        self.proxy_edit.setFixedHeight(CONTROL_HEIGHT)
        grid.addWidget(self.proxy_edit, 2, 1, 1, 2)
        self.check_proxy_button = QPushButton("检测代理")
        self.check_proxy_button.setFixedHeight(CONTROL_HEIGHT)
        self.check_proxy_button.clicked.connect(self.check_proxy)
        grid.addWidget(self.check_proxy_button, 2, 3)
        self.proxy_status = QLabel("尚未检测；手工地址仅用于检测和临时 CLI 试运行。")
        self.proxy_status.setProperty("role", "caption")
        self.proxy_status.setContentsMargins(FIELD_CONTENT_OFFSET, 0, 0, 0)
        grid.addWidget(self.proxy_status, 3, 1, 1, 3)

        grid.addWidget(QLabel("Codex 配置："), 4, 0)
        self.config_path_edit = QLineEdit()
        self.config_path_edit.setReadOnly(True)
        self.config_path_edit.setTextMargins(FIELD_TEXT_MARGIN, 0, FIELD_TEXT_MARGIN, 0)
        self.config_path_edit.setFixedHeight(CONTROL_HEIGHT)
        grid.addWidget(self.config_path_edit, 4, 1, 1, 2)
        self.config_state_label = QLabel("状态：尚未检测")
        self.config_state_label.setMinimumWidth(105)
        self.config_state_label.setFixedHeight(CONTROL_HEIGHT)
        self.config_state_label.setAlignment(Qt.AlignLeft | Qt.AlignVCenter)
        self.config_state_label.setProperty("placement", "inline")
        self.config_state_label.setProperty("role", "caption")
        grid.addWidget(self.config_state_label, 4, 3)

        grid.addWidget(QLabel("配置快照："), 5, 0)
        self.snapshot_combo = QComboBox()
        self.snapshot_combo.setSizeAdjustPolicy(QComboBox.AdjustToMinimumContentsLengthWithIcon)
        self.snapshot_combo.setMinimumContentsLength(10)
        self.snapshot_combo.setMinimumWidth(0)
        self.snapshot_combo.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Fixed)
        self.snapshot_combo.setFixedHeight(CONTROL_HEIGHT)
        self.snapshot_combo.setMaxVisibleItems(7)
        self.snapshot_combo.setItemDelegate(ComboItemDelegate(self.snapshot_combo))
        self.snapshot_combo.view().setTextElideMode(Qt.ElideRight)
        grid.addWidget(self.snapshot_combo, 5, 1, 1, 2)
        self.restore_button = QPushButton("恢复所选快照")
        self.restore_button.setFixedHeight(CONTROL_HEIGHT)
        self.restore_button.clicked.connect(self.restore_snapshot)
        grid.addWidget(self.restore_button, 5, 3)

        actions = QGridLayout()
        actions.setContentsMargins(0, 3, 0, 0)
        actions.setHorizontalSpacing(8)
        self.auto_button = QPushButton("自动检测")
        self.auto_button.clicked.connect(self.auto_detect)
        self.trial_button = QPushButton("临时代理试运行（CLI）")
        self.trial_button.clicked.connect(self.temporary_trial)
        self.preview_button = QPushButton("预览修改")
        self.preview_button.clicked.connect(self.preview_repair)
        self.apply_button = QPushButton("应用持久修复")
        self.apply_button.clicked.connect(self.apply_repair)
        for column, button in enumerate(
            (self.auto_button, self.trial_button, self.preview_button, self.apply_button)
        ):
            button.setFixedHeight(CONTROL_HEIGHT)
            button.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Fixed)
            actions.addWidget(button, 0, column)
            actions.setColumnStretch(column, 1)

        grid.addLayout(actions, 6, 0, 1, 4)
        grid.setColumnStretch(1, 1)
        return group

    def _set_label_state(self, label: QLabel, text: str, role: str) -> None:
        label.setText(text)
        label.setProperty("role", role)
        label.style().unpolish(label)
        label.style().polish(label)

    def _set_ready_state(self) -> None:
        self.trial_button.setEnabled(False)
        self.preview_button.setEnabled(False)
        self.apply_button.setEnabled(False)
        self.restore_button.setEnabled(False)

    def _set_busy(self, busy: bool, message: str = "") -> None:
        self.busy = busy
        if busy:
            focused = QApplication.focusWidget()
            self._focus_before_busy = focused if isinstance(focused, QPushButton) else None
            if self._focus_before_busy is not None:
                self.root_widget.setFocus(Qt.OtherFocusReason)
        for button in (
            self.auto_button,
            self.check_codex_button,
            self.check_proxy_button,
            self.trial_button,
            self.preview_button,
            self.apply_button,
            self.restore_button,
        ):
            button.setEnabled(not busy)
        if busy:
            self.progress_label.setText(message or "正在处理...")
            self.progress_bar.setRange(0, 0)
        else:
            self.progress_bar.setRange(0, 100)
            self.progress_bar.setValue(0)
            self.progress_label.setText("就绪")
            self._refresh_button_state()
            QTimer.singleShot(0, self._restore_previous_focus)

    def _restore_previous_focus(self) -> None:
        button = self._focus_before_busy
        self._focus_before_busy = None
        if button is not None and not self.busy and button.isVisible() and button.isEnabled():
            button.setFocus(Qt.OtherFocusReason)

    def _refresh_button_state(self) -> None:
        path_ok = bool(self.codex_combo.currentText().strip())
        proxy_ok = bool(self.proxy_edit.text().strip())
        self.trial_button.setEnabled(path_ok and proxy_ok and not self.busy)
        self.preview_button.setEnabled(path_ok and not self.busy)
        self.apply_button.setEnabled(path_ok and not self.busy)
        self.restore_button.setEnabled(path_ok and not self.busy)

        state = str(((self.report or {}).get("config") or {}).get("feature_state") or "missing")
        if state == "true":
            self.apply_button.setToolTip("持久代理设置已启用；点击查看当前状态。")
        elif state.startswith("invalid-"):
            self.apply_button.setToolTip("配置存在异常；点击查看处理说明。")
        else:
            self.apply_button.setToolTip("创建快照后写入并验证 Codex 持久代理设置。")

        if self.snapshot_combo.count() > 0:
            self.restore_button.setToolTip("恢复当前选中的配置快照。")
        else:
            self.restore_button.setToolTip("暂无可恢复快照；点击查看说明。")

    def log(self, message: str, *, level: str = "info") -> None:
        timestamp = datetime.now().strftime("%H:%M:%S")
        color = {"error": "#d9534f", "ok": "#157f3b", "warn": "#a15c00"}.get(level, "#27313d")
        self.log_view.append(f'<span style="color:{color}">[{timestamp}] {html.escape(str(message))}</span>')

    def _run_task(self, message: str, function, on_result) -> None:
        if self.busy:
            return
        self._set_busy(True, message)
        task = FunctionTask(function)
        task.signals.result.connect(on_result)
        task.signals.error.connect(lambda text: self._task_error(text))
        task.signals.finished.connect(lambda: self._set_busy(False))
        self.thread_pool.start(task)

    def _task_error(self, message: str) -> None:
        localized = localize_backend_text(message)
        self.log(localized, level="error")
        QMessageBox.critical(self, "操作失败", localized)

    def browse_codex(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "选择 Codex 可执行文件",
            self.codex_combo.currentText().strip(),
            "Codex (*.exe *.cmd *.bat);;所有文件 (*.*)",
        )
        if path:
            self.codex_combo.setEditText(path)
            self.check_codex()

    def auto_detect(self) -> None:
        self.log("开始自动检测 Codex、系统代理和配置状态。")
        self._run_task("正在自动检测...", lambda: self.backend.detect(), self._apply_detection_report)

    def _apply_detection_report(self, report: dict[str, Any]) -> None:
        self.report = report
        engines = report.get("engines") or []
        installation_sources = {item.get("path"): item.get("source") for item in report.get("installations") or []}
        self.codex_combo.blockSignals(True)
        self.codex_combo.clear()
        for engine in engines:
            path = str(engine.get("path") or "")
            if not path:
                continue
            source = installation_sources.get(path, "detected")
            self.codex_combo.addItem(path, {"engine": engine, "source": source})
            self.codex_combo.setItemData(self.codex_combo.count() - 1, f"{engine.get('version')} · {source}", Qt.ToolTipRole)
        recommended = str(report.get("recommended_path") or "")
        if recommended:
            index = self.codex_combo.findText(recommended)
            if index >= 0:
                self.codex_combo.setCurrentIndex(index)
            else:
                self.codex_combo.setEditText(recommended)
        self.codex_combo.blockSignals(False)

        selected = next((e for e in engines if e.get("path") == recommended), None)
        if selected and selected.get("supports_system_proxy"):
            self._set_label_state(
                self.codex_status,
                f"{selected.get('version')} · 已确认支持 respect_system_proxy",
                "ok",
            )
        elif selected:
            self._set_label_state(self.codex_status, "已找到 Codex，但未确认代理功能支持。", "warn")
        else:
            self._set_label_state(self.codex_status, "未找到可验证的 Codex 引擎。", "error")

        proxy = report.get("proxy") or {}
        endpoint = str(proxy.get("display_endpoint") or "")
        if endpoint:
            self.proxy_edit.setText(endpoint)
        if proxy.get("configured") and proxy.get("tcp_reachable") is not False:
            description = {"manual": "系统手工代理", "pac": "PAC", "wpad": "WPAD"}.get(proxy.get("source"), "系统代理")
            suffix = " · TCP 可达" if proxy.get("tcp_reachable") is True else ""
            self._set_label_state(self.proxy_status, f"{description}{suffix}", "ok")
        elif proxy.get("configured"):
            self._set_label_state(self.proxy_status, "系统代理已配置，但端口不可达。", "error")
        else:
            self._set_label_state(self.proxy_status, "未检测到 Windows 系统代理、PAC 或 WPAD。", "warn")

        config = report.get("config") or {}
        self.config_path_edit.setText(str(config.get("path") or ""))
        state = str(config.get("feature_state") or "missing")
        role = "ok" if state == "true" else ("error" if state.startswith("invalid-") else "warn")
        self._set_label_state(self.config_state_label, f"状态：{STATE_TEXT.get(state, state)}", role)
        self._populate_snapshots(report.get("snapshots") or [])
        self._refresh_button_state()
        self.log(
            f"自动检测完成：Codex 候选 {len(engines)} 个，配置状态 {STATE_TEXT.get(state, state)}。",
            level="ok",
        )

    def _populate_snapshots(self, snapshots: list[dict[str, Any]]) -> None:
        self.snapshot_combo.clear()
        for snapshot in snapshots:
            created = str(snapshot.get("created_at_local") or "").replace("T", " ")[:23]
            operation = "应用" if snapshot.get("operation") == "apply" else "恢复"
            before_state = STATE_TEXT.get(str(snapshot.get("before_state")), str(snapshot.get("before_state")))
            after_state = STATE_TEXT.get(str(snapshot.get("after_state")), str(snapshot.get("after_state")))
            result_text = RESULT_TEXT.get(str(snapshot.get("result")), str(snapshot.get("result")))
            text = (
                f"{created} · {operation} · {before_state} → "
                f"{after_state} · {result_text}"
            )
            self.snapshot_combo.addItem(text, snapshot.get("id"))

    def check_codex(self) -> None:
        path = self.codex_combo.currentText().strip()
        if not path:
            QMessageBox.warning(self, "缺少路径", "请先选择或输入 Codex 可执行文件。")
            return
        self.log("正在检测所选 Codex 路径。")
        self._run_task("正在检测 Codex 路径...", lambda: self.backend.check_codex(path), self._show_codex_result)

    def _show_codex_result(self, info: dict[str, Any]) -> None:
        if info.get("supports_system_proxy"):
            self._set_label_state(self.codex_status, f"{info.get('version')} · 路径及代理功能有效", "ok")
            self.log("Codex 路径检测通过。", level="ok")
        else:
            message = str(info.get("error") or "未确认 respect_system_proxy 支持。")
            self._set_label_state(self.codex_status, message, "error")
            self.log(message, level="error")
        self._refresh_button_state()

    def check_proxy(self) -> None:
        endpoint = self.proxy_edit.text().strip()
        if not endpoint:
            self.auto_detect()
            return
        self.log("正在检测输入的代理地址。")
        self._run_task("正在检测代理...", lambda: self.backend.check_proxy(endpoint), self._show_proxy_result)

    def _show_proxy_result(self, info: dict[str, Any]) -> None:
        if info.get("valid") and info.get("tcp_reachable"):
            match_text = " · 与系统代理一致" if info.get("matches_system") else " · 与系统代理不同，仅可临时试运行"
            self.proxy_edit.setText(str(info.get("normalized") or self.proxy_edit.text()))
            self._set_label_state(self.proxy_status, f"代理端口可达{match_text}", "ok" if info.get("matches_system") else "warn")
            self.log("代理检测通过。", level="ok")
        else:
            message = str(info.get("error") or "代理端口不可达。")
            self._set_label_state(self.proxy_status, message, "error")
            self.log(message, level="error")
        self._refresh_button_state()

    def _current_inputs(self) -> tuple[str, str | None]:
        path = self.codex_combo.currentText().strip()
        proxy = self.proxy_edit.text().strip() or None
        return path, proxy

    def preview_repair(self) -> None:
        path, proxy = self._current_inputs()
        if not path:
            QMessageBox.warning(self, "缺少路径", "请先选择 Codex 可执行文件。")
            return
        self.log("正在生成持久修复预览。")
        self._run_task("正在生成修改预览...", lambda: self.backend.plan(path, proxy), self._show_plan)

    def _show_plan(self, plan: dict[str, Any]) -> None:
        errors = "\n".join(f"• {localize_backend_text(item)}" for item in plan.get("errors") or []) or "无"
        warnings = "\n".join(f"• {localize_backend_text(item)}" for item in plan.get("warnings") or []) or "无"
        text = (
            f"配置文件：{plan.get('config', {}).get('path')}\n\n"
            f"计划变更：respect_system_proxy\n"
            f"  {plan.get('before_state')} → {plan.get('after_state')}\n\n"
            f"执行条件：{'通过' if plan.get('can_apply') else '未通过'}\n"
            f"警告：\n{warnings}\n\n错误：\n{errors}"
        )
        QMessageBox.information(self, "持久修改预览", text)
        self.log("修改预览已生成。", level="ok" if plan.get("can_apply") else "warn")

    def apply_repair(self) -> None:
        path, proxy = self._current_inputs()
        if not path:
            QMessageBox.warning(self, "缺少路径", "请先选择或输入 Codex 可执行文件。")
            return

        report = self.report or {}
        config = report.get("config") or {}
        system_proxy = report.get("proxy") or {}
        state = str(config.get("feature_state") or "missing")
        if state == "true":
            self.log("持久代理设置已经启用，本次无需修改。", level="ok")
            QMessageBox.information(
                self,
                "无需修改",
                "Codex 持久代理设置已经启用。\n本次不会写入配置，也不会创建新快照。",
            )
            return
        if state.startswith("invalid-"):
            QMessageBox.warning(
                self,
                "配置需要人工检查",
                "当前 Codex 配置存在重复项或无效值。\n为避免覆盖有效内容，程序不会自动修改。",
            )
            return
        if not system_proxy.get("configured"):
            QMessageBox.warning(
                self,
                "未检测到系统代理",
                "持久修复依赖 Windows 系统代理。请先开启系统代理并重新自动检测。",
            )
            return
        if system_proxy.get("tcp_reachable") is False:
            QMessageBox.warning(
                self,
                "系统代理不可达",
                "Windows 系统代理端口当前不可达，请检查 VPN 或代理软件后重试。",
            )
            return
        answer = QMessageBox.question(
            self,
            "确认持久修改",
            "程序将先创建配置快照，再修改 Codex 用户配置并进行验证。\n"
            "不会修改 Windows 系统代理。是否继续？",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )
        if answer != QMessageBox.Yes:
            return
        self.log("开始创建快照并应用持久修复。")
        self._run_task("正在应用并验证配置...", lambda: self.backend.apply(path, proxy), self._repair_finished)

    def _repair_finished(self, result: dict[str, Any]) -> None:
        if not result.get("changed"):
            self.log("Codex 持久代理设置已经启用，本次未修改配置。", level="ok")
            QMessageBox.information(
                self,
                "无需修改",
                "Codex 持久代理设置已经启用。\n本次未写入配置，也未创建新快照。",
            )
            QTimer.singleShot(100, self.auto_detect)
            return

        self.log(str(result.get("message") or "持久修复完成。"), level="ok")
        snapshot = result.get("snapshot_id")
        if snapshot:
            self.log(f"已创建配置快照：{snapshot}")
        QMessageBox.information(self, "修复完成", "Codex 配置已写入并验证。\n请完全退出并重启 Codex 后使用。")
        QTimer.singleShot(100, self.auto_detect)

    def temporary_trial(self) -> None:
        path, proxy = self._current_inputs()
        if not path or not proxy:
            QMessageBox.warning(self, "缺少输入", "临时试运行需要 Codex CLI 路径和代理地址。")
            return

        def launch() -> dict[str, Any]:
            info = self.backend.check_proxy(proxy)
            if not info.get("valid") or not info.get("tcp_reachable"):
                raise RuntimeError(str(info.get("error") or "代理端口不可达。"))
            if info.get("has_credentials"):
                raise RuntimeError("初版临时试运行不接受包含用户名或密码的代理 URL。")
            pid = launch_temporary_codex(path, str(info.get("normalized") or proxy))
            return {"pid": pid, "proxy": info.get("display_endpoint")}

        self.log("正在准备临时代理试运行；不会修改持久配置。")
        self._run_task("正在启动临时 Codex CLI...", launch, self._trial_started)

    def _trial_started(self, result: dict[str, Any]) -> None:
        self.log(f"已启动临时 Codex CLI（PID {result.get('pid')}），代理 {result.get('proxy')}。", level="ok")
        QMessageBox.information(
            self,
            "临时试运行已启动",
            "已在新控制台启动 Codex CLI。\n代理只对该进程及其子进程有效，退出后自动失效。",
        )

    def restore_snapshot(self) -> None:
        snapshot_id = self.snapshot_combo.currentData()
        path = self.codex_combo.currentText().strip()
        if not path:
            QMessageBox.warning(self, "缺少路径", "请先选择或输入 Codex 可执行文件。")
            return
        if not snapshot_id:
            self.log("当前没有可恢复的配置快照。", level="warn")
            QMessageBox.information(
                self,
                "暂无快照",
                "当前没有可恢复的配置快照。\n只有实际修改配置时才会创建快照。",
            )
            return
        answer = QMessageBox.question(
            self,
            "确认恢复快照",
            "恢复前会先为当前配置创建安全快照，恢复失败时自动还原。是否继续？",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )
        if answer != QMessageBox.Yes:
            return
        self.log(f"开始恢复配置快照：{snapshot_id}")
        self._run_task(
            "正在恢复并验证快照...",
            lambda: self.backend.restore(str(snapshot_id), path),
            self._restore_finished,
        )

    def _restore_finished(self, result: dict[str, Any]) -> None:
        self.log(str(result.get("message") or "快照恢复完成。"), level="ok")
        self.log(f"恢复前安全快照：{result.get('safety_snapshot_id')}")
        QMessageBox.information(self, "恢复完成", "所选 Codex 配置快照已恢复并验证。")
        QTimer.singleShot(100, self.auto_detect)

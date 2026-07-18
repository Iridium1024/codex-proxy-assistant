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
    "The configured Windows proxy is not an HTTP or HTTPS proxy supported by persistent repair.": "Windows 当前代理不是持久修复正式支持的 HTTP/HTTPS 代理。",
    "The configured Windows proxy did not pass the HTTPS route test.": "Windows 当前代理未通过 HTTPS 链路验证。",
    "The proxy entered in the UI is not an HTTP or HTTPS proxy supported by persistent repair.": "输入的代理不是持久修复正式支持的 HTTP/HTTPS 代理。",
    "The proxy entered in the UI did not pass the HTTPS route test.": "输入的代理未通过 HTTPS 链路验证。",
    "PAC or WPAD is detected; static HTTPS endpoint validation is not available and Codex will resolve it at runtime.": "已检测到 PAC/WPAD；静态 HTTPS 端点无法直接验证，将由 Codex 在运行时解析。",
    "The entered proxy differs from the Windows system proxy; persistent repair would not use it.": "输入地址与 Windows 系统代理不同，不能用于持久修复。",
    "Proxy URLs containing a user name or password are not accepted.": "不接受包含用户名或密码的代理地址。",
    "Enter the HTTP or Mixed proxy port shown by the proxy application.": "请输入代理软件显示的 HTTP/Mixed 端口。",
    "Use an HTTP or Mixed proxy port. SOCKS is recognized only for limited temporary use.": "请使用 HTTP/Mixed 端口；SOCKS 仅作为有限的临时支持。",
    "Start the proxy application or verify its HTTP or Mixed port, then retry.": "请启动代理软件，或核对 HTTP/Mixed 端口后重试。",
    "Verify that the selected port is the HTTP or Mixed proxy port and that the current node can reach HTTPS sites.": "请确认所选的是 HTTP/Mixed 端口，并检查当前节点能否访问 HTTPS。",
    "Check the current proxy node and retry, or switch to another node.": "请检查当前代理节点并重试，或切换节点。",
    "Confirm that the proxy application is running and the selected port is correct.": "请确认代理软件正在运行且端口正确。",
    "The connection was interrupted; verify the HTTP or Mixed port and switch proxy nodes if needed.": "连接被中断；请核对 HTTP/Mixed 端口，必要时切换节点。",
}

TARGET_KIND_TEXT = {"desktop": "Codex Desktop", "cli": "Codex CLI"}
TARGET_SOURCE_TEXT = {
    "user_selected": "手动选择",
    "appx": "Microsoft Store",
    "running_process": "正在运行的程序",
    "standard_path": "标准安装位置",
    "npm": "npm",
    "path": "PATH",
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
        self.recommended_next_step = "就绪"
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
        # Keep the five-column feedback row aligned to the equal-width action buttons.
        feedback_row.setHorizontalSpacing(3)
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
        feedback_row.addWidget(self.progress_bar, 0, 2, 1, 3)
        for column in range(5):
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
        self.codex_combo.currentIndexChanged.connect(self._selected_target_changed)
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
        self.proxy_edit.setPlaceholderText("例如：http://127.0.0.1:XXXX")
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

        actions = QHBoxLayout()
        actions.setContentsMargins(0, 3, 0, 0)
        actions.setSpacing(8)
        self.auto_button = QPushButton("自动检测")
        self.auto_button.clicked.connect(self.auto_detect)
        self.trial_button = QPushButton("临时 CLI 试运行")
        self.trial_button.clicked.connect(self.temporary_trial)
        self.preview_button = QPushButton("预览修改")
        self.preview_button.clicked.connect(self.preview_repair)
        self.apply_button = QPushButton("应用持久修复")
        self.apply_button.clicked.connect(self.apply_repair)
        self.connection_button = QPushButton("验证实际连接")
        self.connection_button.clicked.connect(self.test_real_connection)
        action_buttons = (
            self.auto_button,
            self.trial_button,
            self.preview_button,
            self.connection_button,
            self.apply_button,
        )
        for button in action_buttons:
            button.setFixedHeight(CONTROL_HEIGHT)
            button.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Fixed)
            button.setMinimumWidth(0)
            actions.addWidget(button, 1)

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
        self.connection_button.setEnabled(False)
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
            self.connection_button,
            self.restore_button,
        ):
            button.setEnabled(not busy)
        if busy:
            self.progress_label.setText(message or "正在处理...")
            self.progress_bar.setRange(0, 0)
        else:
            self.progress_bar.setRange(0, 100)
            self.progress_bar.setValue(0)
            self.progress_label.setText(self.recommended_next_step)
            self.progress_label.setToolTip(self.recommended_next_step)
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
        self.connection_button.setEnabled(path_ok and not self.busy)
        self.restore_button.setEnabled(path_ok and not self.busy)

        if not path_ok:
            missing_tip = "尚未找到 Codex；请先自动检测或手动选择路径。"
            self.preview_button.setToolTip(missing_tip)
            self.apply_button.setToolTip(missing_tip)
            self.connection_button.setToolTip(missing_tip)
        else:
            self.preview_button.setToolTip("查看将要修改的配置和当前执行条件。")
            self.connection_button.setToolTip("主动发送一个最小真实请求；会使用当前登录状态并可能消耗少量额度。")
        self.trial_button.setToolTip(
            "使用当前代理仅启动一次 CLI，不写入配置。"
            if path_ok and proxy_ok
            else "临时 CLI 试运行需要 Codex 路径和已填写的代理地址。"
        )

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
        self.codex_combo.blockSignals(True)
        self.codex_combo.clear()
        for engine in engines:
            path = str(engine.get("path") or "")
            if not path:
                continue
            source = str(engine.get("source") or "path")
            self.codex_combo.addItem(path, {"engine": engine, "source": source})
            kind_text = TARGET_KIND_TEXT.get(str(engine.get("kind")), "Codex")
            source_text = TARGET_SOURCE_TEXT.get(source, source)
            self.codex_combo.setItemData(
                self.codex_combo.count() - 1,
                f"{kind_text} · {engine.get('version')} · {source_text}",
                Qt.ToolTipRole,
            )
        recommended = str(report.get("recommended_path") or "")
        if recommended:
            index = self.codex_combo.findText(recommended)
            if index >= 0:
                self.codex_combo.setCurrentIndex(index)
            else:
                self.codex_combo.setEditText(recommended)
        self.codex_combo.blockSignals(False)

        selected = report.get("recommended") or next(
            (e for e in engines if e.get("path") == recommended), None
        )
        self._show_selected_target_status(selected)
        for skipped in report.get("skipped") or []:
            path = str(skipped.get("path") or "未知路径")
            if skipped.get("error_class") == "probe_timeout":
                self.log(f"一个 Codex 候选检测超时，已跳过：{path}", level="warn")
            elif skipped.get("error"):
                self.log(f"一个 Codex 候选无法验证，已跳过：{path}", level="warn")

        proxy = report.get("proxy") or {}
        endpoint = str(proxy.get("display_endpoint") or "")
        if endpoint:
            self.proxy_edit.setText(endpoint)
        if proxy.get("source") in {"pac", "wpad"}:
            description = "PAC" if proxy.get("source") == "pac" else "WPAD"
            self._set_label_state(
                self.proxy_status,
                f"已检测到 {description} · 尚未完成静态端点验证，将由 Codex 运行时解析",
                "warn",
            )
        elif proxy.get("configured") and proxy.get("https_reachable") is True:
            suffix = " · 使用兼容的证书吊销回退" if proxy.get("used_ssl_no_revoke") else ""
            self._set_label_state(self.proxy_status, f"系统手工代理 · 可访问 HTTPS{suffix}", "ok")
        elif proxy.get("configured") and proxy.get("tcp_reachable") is False:
            self._set_label_state(self.proxy_status, "系统代理已配置，但端口不可达。", "error")
        elif proxy.get("configured"):
            next_step = str(proxy.get("next_step") or "请确认使用代理软件的 HTTP/Mixed 端口。")
            self._set_label_state(
                self.proxy_status,
                f"代理端口已开放，但 HTTPS 验证失败；{localize_backend_text(next_step)}",
                "error",
            )
        else:
            self._set_label_state(self.proxy_status, "未检测到 Windows 系统代理、PAC 或 WPAD。", "warn")

        config = report.get("config") or {}
        self.config_path_edit.setText(str(config.get("path") or ""))
        state = str(config.get("feature_state") or "missing")
        role = "ok" if state == "true" else ("error" if state.startswith("invalid-") else "warn")
        config_summary = (
            "无需修改"
            if state == "true"
            else ("需人工检查" if state.startswith("invalid-") else "可应用修复")
        )
        self._set_label_state(self.config_state_label, f"状态：{config_summary}", role)
        self._populate_snapshots(report.get("snapshots") or [])
        self.recommended_next_step = self._recommended_step(selected, proxy, state)
        self._refresh_button_state()
        self.log(
            f"自动检测完成：Codex 候选 {len(engines)} 个，配置状态 {STATE_TEXT.get(state, state)}。",
            level="ok",
        )

    @staticmethod
    def _recommended_step(
        selected: dict[str, Any] | None, proxy: dict[str, Any], config_state: str
    ) -> str:
        if not selected:
            return "下一步：安装或选择 Codex"
        if not selected.get("supports_system_proxy"):
            return "下一步：更新或改选 Codex"
        if not proxy.get("configured"):
            return "下一步：开启系统代理"
        if proxy.get("source") == "manual" and proxy.get("tcp_reachable") is False:
            return "下一步：启动代理软件"
        if proxy.get("source") == "manual" and proxy.get("https_reachable") is not True:
            return "下一步：选择 HTTP/Mixed 端口"
        if config_state.startswith("invalid-"):
            return "下一步：人工检查配置"
        if config_state == "true":
            return "下一步：重启 Codex 或验证连接"
        return "下一步：预览并应用修复"

    def _selected_target_changed(self) -> None:
        data = self.codex_combo.currentData()
        engine = data.get("engine") if isinstance(data, dict) else None
        if engine:
            self._show_selected_target_status(engine)
        self._refresh_button_state()

    def _show_selected_target_status(self, engine: dict[str, Any] | None) -> None:
        if not engine:
            self._set_label_state(
                self.codex_status,
                "未找到 Codex；请安装或更新后重试，也可手动选择路径。",
                "error",
            )
            return
        kind_text = TARGET_KIND_TEXT.get(str(engine.get("kind")), "Codex")
        version = str(engine.get("version") or "版本未知")
        if engine.get("timed_out"):
            self._set_label_state(
                self.codex_status,
                f"当前目标：{kind_text} · 检测超时，已跳过；可重新检测或改选其他安装。",
                "warn",
            )
        elif engine.get("supports_system_proxy"):
            self._set_label_state(
                self.codex_status,
                f"当前目标：{kind_text} · {version} · 支持系统代理",
                "ok",
            )
        elif engine.get("runnable"):
            self._set_label_state(
                self.codex_status,
                f"当前目标：{kind_text} · {version} · 请更新 Codex 以支持系统代理",
                "warn",
            )
        else:
            self._set_label_state(
                self.codex_status,
                f"当前目标：{kind_text} · 无法验证；请重新选择或重新检测。",
                "error",
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
            kind_text = TARGET_KIND_TEXT.get(str(info.get("kind")), "Codex")
            self._set_label_state(
                self.codex_status,
                f"当前目标：{kind_text} · {info.get('version')} · 支持系统代理",
                "ok",
            )
            self.log("Codex 路径检测通过。", level="ok")
        else:
            if info.get("error_class") == "probe_timeout":
                message = "所选 Codex 检测超时；请重试或重新选择路径。"
            elif info.get("error_class") == "path_missing":
                message = "所选路径已失效；请重新选择或运行自动检测。"
            elif info.get("runnable"):
                message = "已找到 Codex，但当前版本不支持系统代理，请更新后重试。"
            else:
                message = str(info.get("error") or "无法验证所选 Codex。")
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
        if info.get("valid") and info.get("https_reachable") is True:
            match_text = " · 与系统代理一致" if info.get("matches_system") else " · 与系统代理不同，仅可临时试运行"
            self.proxy_edit.setText(str(info.get("normalized") or self.proxy_edit.text()))
            support_text = "" if info.get("persistent_supported") else " · SOCKS 为有限支持"
            self._set_label_state(
                self.proxy_status,
                f"代理可访问 HTTPS{match_text}{support_text}",
                "ok" if info.get("matches_system") and info.get("persistent_supported") else "warn",
            )
            self.log("代理 HTTPS 链路验证通过。", level="ok")
        elif info.get("tcp_reachable"):
            message = str(info.get("next_step") or info.get("error") or "端口已开放，但无法作为 HTTPS 代理使用。")
            self._set_label_state(
                self.proxy_status,
                f"端口已开放，但 HTTPS 验证失败；{localize_backend_text(message)}",
                "error",
            )
            self.log("端口已开放，但未通过 HTTPS 代理验证。", level="error")
        else:
            message = localize_backend_text(info.get("error") or "代理端口不可达。")
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
        if system_proxy.get("source") == "manual" and system_proxy.get("https_reachable") is not True:
            QMessageBox.warning(
                self,
                "系统代理未通过 HTTPS 验证",
                "代理端口虽然可能已开放，但尚不能确认它能转发 HTTPS。\n"
                "请在代理软件中选择 HTTP/Mixed 端口并重新检测。",
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
        proxy_ok = ((self.report or {}).get("proxy") or {}).get("https_reachable") is True
        QMessageBox.information(
            self,
            "修复完成",
            "配置已写入并被 Codex 读取：是\n"
            f"代理 HTTPS 检测：{'成功' if proxy_ok else '尚未确认'}\n"
            "Codex 实际请求：尚未验证\n\n"
            "请完全退出并重启 Codex；如需进一步确认，可主动点击“验证实际连接”。",
        )
        QTimer.singleShot(100, self.auto_detect)

    def test_real_connection(self) -> None:
        path = self.codex_combo.currentText().strip()
        if not path:
            QMessageBox.warning(self, "缺少路径", "请先选择或检测 Codex。")
            return
        answer = QMessageBox.question(
            self,
            "确认验证实际连接",
            "此操作会使用当前 Codex 登录状态发送一个最小、无工具的临时请求，"
            "可能消耗少量 Codex 额度。\n不会修改配置。是否继续？",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )
        if answer != QMessageBox.Yes:
            return
        self.log("用户已确认，开始执行最小 Codex 实际连接验证。")
        self._run_task(
            "正在验证实际连接...",
            lambda: self.backend.test_connection(path),
            self._show_connection_result,
        )

    def _show_connection_result(self, result: dict[str, Any]) -> None:
        if result.get("success"):
            self.log("Codex 最小实际请求成功。", level="ok")
            QMessageBox.information(
                self,
                "连接验证成功",
                "配置读取：已验证\n代理 HTTPS：请参见代理状态\nCodex 实际请求：成功",
            )
            return
        if not result.get("attempted"):
            message = "当前 Codex 不支持可靠的非交互验证；配置状态不受影响，未发送真实请求。"
        elif result.get("timed_out"):
            message = "实际请求超时，相关进程已终止。配置不会因此自动回滚。"
        else:
            message = (
                "实际请求未成功。配置不会自动回滚；请检查账号、代理节点、服务状态，"
                "或 Desktop 的附属连接。"
            )
        self.log(message, level="warn")
        QMessageBox.warning(self, "连接尚未确认", message)

    def temporary_trial(self) -> None:
        path, proxy = self._current_inputs()
        if not path or not proxy:
            QMessageBox.warning(self, "缺少输入", "临时试运行需要 Codex CLI 路径和代理地址。")
            return

        def launch() -> dict[str, Any]:
            info = self.backend.check_proxy(proxy)
            if not info.get("valid") or info.get("https_reachable") is not True:
                raise RuntimeError(str(info.get("next_step") or info.get("error") or "代理未通过 HTTPS 验证。"))
            if info.get("has_credentials"):
                raise RuntimeError("临时试运行不支持包含用户名或密码的代理 URL。")
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

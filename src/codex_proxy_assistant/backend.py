from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


class BackendError(RuntimeError):
    pass


def resource_root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(getattr(sys, "_MEIPASS")).resolve()
    return Path(__file__).resolve().parents[2]


class PowerShellBackend:
    def __init__(self) -> None:
        self.cli_script = resource_root() / "powershell" / "CodexProxy.Cli.ps1"
        if not self.cli_script.is_file():
            raise BackendError(f"缺少后端脚本：{self.cli_script}")

    @staticmethod
    def _startup_options() -> dict[str, Any]:
        if os.name != "nt":
            return {}
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        return {
            "startupinfo": startup,
            "creationflags": getattr(subprocess, "CREATE_NO_WINDOW", 0),
        }

    def call(
        self,
        action: str,
        *,
        codex_path: str | None = None,
        proxy_endpoint: str | None = None,
        config_path: str | None = None,
        snapshot_id: str | None = None,
        timeout: int = 45,
    ) -> Any:
        command = [
            "powershell.exe",
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(self.cli_script),
            "-Action",
            action,
        ]
        for switch, value in (
            ("-CodexPath", codex_path),
            ("-ProxyEndpoint", proxy_endpoint),
            ("-ConfigPath", config_path),
            ("-SnapshotId", snapshot_id),
        ):
            if value:
                command.extend([switch, value])

        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
            **self._startup_options(),
        )
        stdout = completed.stdout.decode("utf-8-sig", errors="replace").strip()
        stderr = completed.stderr.decode("utf-8-sig", errors="replace").strip()
        if not stdout:
            raise BackendError(stderr or f"后端没有返回结果（退出码 {completed.returncode}）")
        try:
            envelope = json.loads(stdout.splitlines()[-1])
        except json.JSONDecodeError as exc:
            raise BackendError(f"无法解析后端结果：{stdout[-500:]}") from exc
        if not envelope.get("ok"):
            raise BackendError(str(envelope.get("error") or stderr or "后端操作失败"))
        return envelope.get("data")

    def detect(self, codex_path: str | None = None) -> dict[str, Any]:
        return self.call("detect", codex_path=codex_path)

    def check_codex(self, path: str) -> dict[str, Any]:
        return self.call("check-codex", codex_path=path)

    def check_proxy(self, endpoint: str) -> dict[str, Any]:
        return self.call("check-proxy", proxy_endpoint=endpoint)

    def plan(self, codex_path: str, proxy_endpoint: str | None) -> dict[str, Any]:
        return self.call("plan", codex_path=codex_path, proxy_endpoint=proxy_endpoint)

    def apply(self, codex_path: str, proxy_endpoint: str | None) -> dict[str, Any]:
        return self.call("apply", codex_path=codex_path, proxy_endpoint=proxy_endpoint)

    def restore(self, snapshot_id: str, codex_path: str) -> dict[str, Any]:
        return self.call("restore", snapshot_id=snapshot_id, codex_path=codex_path)


def launch_temporary_codex(codex_path: str, proxy_endpoint: str) -> int:
    path = Path(codex_path).expanduser().resolve()
    if not path.is_file():
        raise BackendError("所选 Codex 可执行文件不存在。")
    if path.suffix.lower() not in {".cmd", ".bat", ".exe"}:
        raise BackendError("临时试运行仅支持 .cmd、.bat 或 .exe。")

    env = os.environ.copy()
    for name in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"):
        env[name] = proxy_endpoint

    creationflags = getattr(subprocess, "CREATE_NEW_CONSOLE", 0) if os.name == "nt" else 0
    if path.suffix.lower() in {".cmd", ".bat"}:
        process = subprocess.Popen(
            ["cmd.exe", "/k", "call", str(path)],
            env=env,
            creationflags=creationflags,
        )
    else:
        process = subprocess.Popen([str(path)], env=env, creationflags=creationflags)
    return int(process.pid)

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from PyQt5.QtCore import QObject, QRunnable, pyqtSignal, pyqtSlot


class TaskSignals(QObject):
    result = pyqtSignal(object)
    error = pyqtSignal(str)
    finished = pyqtSignal()


class FunctionTask(QRunnable):
    def __init__(self, function: Callable[[], Any]) -> None:
        super().__init__()
        self.function = function
        self.signals = TaskSignals()

    @pyqtSlot()
    def run(self) -> None:
        try:
            self.signals.result.emit(self.function())
        except Exception as exc:  # GUI boundary: convert backend errors to text.
            self.signals.error.emit(str(exc))
        finally:
            self.signals.finished.emit()

"""Compute kernels compiled ahead of time.

These are written in the project's ``.pyx`` dialect, which the overlay spec
in ``.indexion/kgfs`` declares as an extension of Python.
"""

from dataclasses import dataclass


@dataclass
class Window:
    """A half-open interval over a sample buffer."""

    start: int
    end: int

    def width(self) -> int:
        """Number of samples the window covers."""
        return self.end - self.start


def moving_average(samples, window):
    """Average ``samples`` over ``window``.

    The caller guarantees the window lies inside the buffer, so no bounds
    check is performed here.
    """
    total = 0.0
    for index in range(window.start, window.end):
        total += samples[index]
    return total / window.width()

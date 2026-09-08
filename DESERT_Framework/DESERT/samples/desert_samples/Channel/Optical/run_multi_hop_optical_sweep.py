"""Compatibility entry point for the optical/acoustic comparison runner.
The implementation now lives in ``run_optical_acoustic_comparison.py``.
Keeping this filename means existing commands continue to run, while the
runner also tests the new acoustic single-link baseline.
"""

from run_optical_acoustic_comparison import main

if __name__ == "__main__":
    main()

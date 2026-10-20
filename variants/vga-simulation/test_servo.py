#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Ejecuta test_servo.gcode usando el controlador CNC fiable."""

from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent
command = [sys.executable, str(root / "cnc-python.py"), str(root / "test_servo.gcode")]
raise SystemExit(subprocess.call(command))

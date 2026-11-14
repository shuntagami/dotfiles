#!/usr/bin/env python3
"""Compatibility entry point for Git-backed personal MulmoTerminal project settings."""
import runpy
from pathlib import Path

if __name__ == '__main__':
    runpy.run_path(str(Path(__file__).with_name('sync-mulmoterminal-projects.py')), run_name='__main__')

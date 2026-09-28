"""Loads web/models/config.json, written by matlab/s25_export_onnx.m.

Every threshold and constant the Python side uses comes from that file, so the
web app cannot drift from the MATLAB pipeline it was measured as.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np

MODEL_DIR = Path(__file__).resolve().parent.parent / 'models'


class _Config:
    def __init__(self):
        self._raw = None

    def _load(self):
        if self._raw is None:
            with open(MODEL_DIR / 'config.json', encoding='utf-8') as f:
                self._raw = json.load(f)
        return self._raw

    def __getattr__(self, name):
        if name.startswith('_'):
            raise AttributeError(name)
        raw = self._load()
        v = raw[name]
        return np.asarray(v, np.float32) if name in ('im_mean', 'im_std') else v

    def strel(self, name):
        return np.asarray(self._load()['strel'][name], bool)


CFG = _Config()

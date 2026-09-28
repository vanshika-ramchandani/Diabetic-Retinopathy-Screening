"""ONNX Runtime sessions for the three networks, loaded once per process.

CUDA is used when onnxruntime-gpu finds a GPU (Colab T4); otherwise CPU (HF Space).
The ONNX files are exported from MATLAB by matlab/s25_export_onnx.m and are
NCHW float32 in, NCHW float32 out.
"""
from __future__ import annotations

import threading

import numpy as np
import onnxruntime as ort

from .config import MODEL_DIR

_lock = threading.Lock()
_sessions: dict[str, ort.InferenceSession] = {}


def providers():
    avail = ort.get_available_providers()
    return [p for p in ('CUDAExecutionProvider', 'CPUExecutionProvider') if p in avail]


def session(name: str) -> ort.InferenceSession:
    with _lock:
        if name not in _sessions:
            opts = ort.SessionOptions()
            opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
            src = str(MODEL_DIR / f'{name}.onnx')
            if name == 'grader':
                src = _with_cam_output(src)
            _sessions[name] = ort.InferenceSession(src, sess_options=opts, providers=providers())
        return _sessions[name]


def _with_cam_output(path: str) -> bytes:
    """Expose the feature map that feeds global average pooling as a FIRST graph output.

    Grad-CAM needs it (see grade.py); MATLAB's export only emits the softmax.
    Done in memory at load time so the shipped .onnx stays exactly as exported.
    """
    import onnx
    m = onnx.load(path)
    gap = [n for n in m.graph.node if n.op_type == 'GlobalAveragePool']
    feat = gap[-1].input[0]
    vi = onnx.helper.make_tensor_value_info(feat, onnx.TensorProto.FLOAT, None)
    m.graph.output.insert(0, vi)
    return m.SerializeToString()


def device() -> str:
    """What a session actually runs on. onnxruntime-gpu silently falls back to CPU when the
    CUDA/cuDNN libraries don't match, so the installed package is not evidence of a GPU."""
    return 'GPU (CUDA)' if 'CUDAExecutionProvider' in session('lesion').get_providers() else 'CPU'


def run(name: str, X_nhwc: np.ndarray) -> list[np.ndarray]:
    """Run a net on an NHWC float32 batch; returns every graph output, NHWC where 4-D."""
    s = session(name)
    X = np.ascontiguousarray(X_nhwc.transpose(0, 3, 1, 2), dtype=np.float32)
    outs = s.run(None, {s.get_inputs()[0].name: X})
    return [o.transpose(0, 2, 3, 1) if o.ndim == 4 else o for o in outs]


def warmup():
    for n in ('lesion', 'vessel', 'grader'):
        session(n)

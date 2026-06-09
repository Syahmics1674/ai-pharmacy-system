"""
MedScan Pro — Medicine OCR Inventory System
============================================
v4  Changes (on top of v3)

  SCAN ROI / CAMERA — core fix
  • Camera auto-negotiates the best resolution from a priority list
    (4 K → FHD → HD) so the IMX378 USB-C is always used at its highest
    sustainable rate.  No more manually tweaking CAMERA_WIDTH / HEIGHT.
  • All processing (YOLO, OCR, display, save) works on a fixed
    SCAN_SIZE × SCAN_SIZE square cropped from the 300 × 300 mm physical
    tray.  Changing capture resolution or SCAN_ROI never alters perceived
    text size — the downstream pipeline always sees the same pixel density.
  • SHOW_ROI_OVERLAY draws subtle corner viewfinder marks on the live feed.
  • Interactive CALIBRATION MODE: press "⊞ Calibrate" to see the full raw
    frame with the ROI rectangle overlaid.  Four spinboxes let you tune
    x1/y1/x2/y2 live; "Auto-center", "Make Square", "Copy SCAN_ROI" and
    "Apply & Resume" buttons make first-time setup easy.  The result is
    saved to scan_roi_config.json and reloaded on the next run.

  CODE QUALITY
  • Bare `except Exception: continue` blocks replaced with logged warnings.
  • `_on_confirm_dispense` refactored into `_group_dispense_items` +
    `_execute_dispense` (each ~30 lines).
  • `OCR_SKIP_STRIP_TOP` constant now actually used at runtime.
  • Scan history capped at MAX_HISTORY_ENTRIES (default 200).
  • Public functions annotated with type hints.
  • SAVE_DIR uses script-relative path — no CWD dependency.
  • SSL bypass annotated with a TODO instead of being silently hidden.
  • Module-level logging replaces bare print() calls throughout.

  v3 features unchanged
  • CLASS MERGE: YOLO classes 0 (Box) + 1 (Strip Back) → "Medicine".
  • POST-YOLO IoU dedup collapses overlapping same-object detections.
  • Hybrid OCR: fast → full escalation.
"""

from __future__ import annotations

import os
# Fix OpenMP duplicate runtime initialization conflict (common PyTorch + PaddleOCR conflict)
os.environ["KMP_DUPLICATE_LIB_OK"] = "TRUE"
# Disable PaddlePaddle's oneDNN (MKLDNN) to prevent "ConvertPirAttribute2RuntimeAttribute" unimplemented error on CPU
os.environ["PADDLE_PDX_ENABLE_MKLDNN_BYDEFAULT"] = "0"
os.environ["FLAGS_use_mkldnn"] = "0"
import sys, re, ssl, cv2, json, logging
import numpy as np
import pandas as pd
from datetime import datetime
from difflib import SequenceMatcher
from typing import Optional, List, Tuple, Dict, Any

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("MedScan")

# ── Local SQLite + Supabase sync ──────────────────────────────────────────────
try:
    from sync_engine import init_local_db, confirm_dispense as _confirm_dispense_fn, sync_unsynced_transactions
    INVENTORY_SYNC_AVAILABLE = True
except Exception as _import_err:
    log.warning("Inventory sync unavailable: %s", _import_err)
    INVENTORY_SYNC_AVAILABLE = False

# ── SSL ───────────────────────────────────────────────────────────────────────
# TODO: replace with a proper CA bundle once the certificate issue is resolved.
#       Disabling SSL verification globally is a security risk in production.
ssl._create_default_https_context = ssl._create_unverified_context
os.environ["DISABLE_MODEL_SOURCE_CHECK"] = "True"

# PRE-IMPORT TORCH & PADDLE TO PREVENT WinError 1114 DLL CONFLICTS WITH PYQT5
try:
    import importlib.util
    for pkg in ["torch", "paddle"]:
        spec = importlib.util.find_spec(pkg)
        if spec and spec.submodule_search_locations:
            pkg_dir = spec.submodule_search_locations[0]
            pkg_lib = os.path.join(pkg_dir, "lib")
            if os.path.isdir(pkg_lib) and hasattr(os, "add_dll_directory"):
                try:
                    os.add_dll_directory(pkg_lib)
                except Exception:
                    pass
except Exception:
    pass

try:
    import torch
    import ultralytics
except Exception:
    pass
from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QFrame, QScrollArea, QStatusBar, QProgressBar,
    QGraphicsDropShadowEffect, QGridLayout, QTextEdit, QTabWidget,
    QFileDialog, QMessageBox, QShortcut, QSizePolicy, QSpinBox,
)
from PyQt5.QtCore import Qt, QThread, pyqtSignal, QTimer, QPropertyAnimation, QRect, QEasingCurve
from PyQt5.QtGui import (
    QPixmap, QImage, QColor, QPainter, QFont, QPalette, QBrush,
    QKeySequence, QPen, QLinearGradient, QFontDatabase,
)

# ══════════════════════════════════════════════════════════════════════════════
#  CONFIG
# ══════════════════════════════════════════════════════════════════════════════

MODEL_PATH = "best.pt"

DATABASE_CANDIDATES: List[str] = [
    "malaysia_inventory_ocr_inventory_corrected_with_photo_items.csv",
]

# Script-relative output folder — does not depend on the working directory.
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SAVE_DIR     = os.path.join(_SCRIPT_DIR, "Med_Output")
os.makedirs(SAVE_DIR, exist_ok=True)

ROI_CONFIG_PATH = os.path.join(_SCRIPT_DIR, "scan_roi_config.json")

# ── Class map (v3: Box + Strip Back unified as "Medicine") ────────────────────
CLASS_NAMES         : Dict[int, str] = {0: "Medicine", 1: "Medicine", 2: "Strip Top"}
DEDUP_IOU_THRESHOLD : float = 0.40
MAX_HISTORY_ENTRIES : int   = 200

# ── Camera — Waveshare IMX378 USB-C ──────────────────────────────────────────
CAMERA_INDEX   : int = 0
CAMERA_BACKEND       = None      # None = auto; try cv2.CAP_V4L2 on Linux
CAMERA_ROTATE  : int = 0         # 0 / 90 / 180 / 270
CAMERA_FLIP_HORIZONTAL : bool = False
CAMERA_FLIP_VERTICAL   : bool = False

# The CameraThread tries each resolution in order and keeps the first one
# the camera actually delivers (within 5 % tolerance).
# USB 2.0 usually caps reliable capture at FHD (1920×1080).
CAMERA_RESOLUTION_CANDIDATES: List[Tuple[int, int]] = [
    (3840, 2160),   # 4 K  — best text detail; needs USB 3.0
    (1920, 1080),   # FHD  — excellent balance; USB 2.0 OK
    (1280,  720),   # HD   — minimum acceptable
]

# ── Scan Area — 300 mm × 300 mm physical tray ─────────────────────────────────
#
# The IMX378 wide-angle lens sees a much larger area than the 300×300 mm tray.
# We crop a rectangular ROI from the raw camera frame that covers exactly the
# physical scan surface, then resize to SCAN_SIZE × SCAN_SIZE for all
# downstream processing (YOLO, OCR, display, save).
#
# Changing SCAN_ROI re-maps which part of the camera view is used.
# Changing capture resolution (via CAMERA_RESOLUTION_CANDIDATES) does not
# affect text density because the output is always SCAN_SIZE × SCAN_SIZE.
#
# SCAN_ROI:
#   None  → auto-centered square: side = min(raw_w, raw_h), horizontally
#            centred.  Good enough to start; use Calibrate mode to tune.
#   tuple → (x1, y1, x2, y2) in raw-frame pixel coordinates, saved and
#            reloaded from scan_roi_config.json automatically.
#
SCAN_ROI  : Optional[Tuple[int, int, int, int]] = None   # overridden at startup from config file
SCAN_SIZE : int  = 1280
SCAN_OUTPUT_W : int = 1280
SCAN_OUTPUT_H : int = 780     # square output fed to YOLO and OCR

# Draw corner viewfinder marks on the live scan feed
SHOW_ROI_OVERLAY : bool = True

# ── YOLO ─────────────────────────────────────────────────────────────────────
YOLO_FAST_MODE       : bool  = False
YOLO_CAPTURE_CONF    : float = 0.25
YOLO_CAPTURE_IOU     : float = 0.30
YOLO_CAPTURE_IMGSZ   : int   = 960
YOLO_CAPTURE_AUGMENT : bool  = not YOLO_FAST_MODE
YOLO_CAPTURE_MAX_DET : int   = 10 if YOLO_FAST_MODE else 20

# ── Hybrid OCR ───────────────────────────────────────────────────────────────
OCR_FAST_MODE                : bool  = True
OCR_HYBRID_QUALITY_THRESHOLD : float = 0.78
OCR_HYBRID_MIN_GOOD_TOKENS   : int   = 2
OCR_MAX_DETECTIONS           : int   = 5
OCR_SKIP_STRIP_TOP           : bool  = True   # now checked at runtime
OCR_PAD                      : int   = 12 if OCR_FAST_MODE else 18
OCR_UPSCALE_TARGET           : int   = 220 if OCR_FAST_MODE else 300
NAME_THRESHOLD               : float = 2 / 3
STRENGTH_BOOST               : float = 0.30
OCR_MIN_CONF                 : float = 0.75
OCR_MIN_LETTERS              : int   = 3

# ── UI palette ────────────────────────────────────────────────────────────────
C_BG      = "#06091A";  C_PANEL  = "#0B1228";  C_BORDER = "#162040"
C_ACCENT  = "#00D4F5";  C_ACCENT2= "#00FF9D";  C_WARN   = "#FFB800"
C_ERR     = "#FF4B6E";  C_TEXT   = "#C8D8EE";  C_MUTED  = "#3A5575"
C_CARD    = "#0E1830"

CATEGORY_COLORS: Dict[str, str] = {
    "Analgesic":    "#FF6B6B", "Antibiotic":    "#4ECDC4",
    "GI":           "#45B7D1", "Antihistamine": "#A8E6CF",
    "Respiratory":  "#7BC8A4", "Chronic":       "#FFD93D",
    "ENT":          "#C3B1E1", "Topical":       "#F4A261",
    "Antiseptic":   "#E76F51", "Eye":           "#457B9D",
    "Injection":    "#E63946", "Maternal":      "#F28482",
    "Wound Care":   "#84A98C", "Supply":        "#B5B5B5",
    "Steroid":      "#FBBF24", "Sedative":      "#818CF8",
}

DOSAGE_ICONS: Dict[str, str] = {
    "Tablet":                    "💊", "Capsule":               "💊",
    "Chewable Tablet":           "💊", "Extended Release Tablet":"💊",
    "Caplet":                    "💊", "Syrup":                 "🍶",
    "Suspension":                "🍶", "Oral Solution":         "🍶",
    "Drops":                     "💧", "Eye Drops":             "👁️",
    "Nasal Drops":               "👃", "Nasal Spray":           "💨",
    "Inhaler":                   "💨", "Cream":                 "🧴",
    "Lotion":                    "🧴", "Injection":             "💉",
    "IV Infusion":               "💉", "Lozenge":               "🟠",
    "Powder Sachet":             "📦", "Sachet":                "📦",
    "Plaster":                   "🩹", "Tape":                  "🩹",
    "Wound Care":                "🩹", "Mask":                  "😷",
    "Needle":                    "💉", "Syringe":               "💉",
    "Solution":                  "🧪", "Irrigation Solution":   "🧪",
}

# ══════════════════════════════════════════════════════════════════════════════
#  SCAN ROI CONFIG  (load / save)
# ══════════════════════════════════════════════════════════════════════════════

def _load_roi_config() -> Optional[Tuple[int, int, int, int]]:
    try:
        with open(ROI_CONFIG_PATH) as fh:
            data = json.load(fh)
        roi = data.get("scan_roi")
        if roi and len(roi) == 4:
            return tuple(int(v) for v in roi)   # type: ignore[return-value]
    except FileNotFoundError:
        pass
    except Exception as exc:
        log.warning("Failed to load ROI config: %s", exc)
    return None


def _save_roi_config(x1: int, y1: int, x2: int, y2: int) -> None:
    try:
        with open(ROI_CONFIG_PATH, "w") as fh:
            json.dump({"scan_roi": [x1, y1, x2, y2]}, fh, indent=2)
        log.info("ROI config saved: (%d, %d) → (%d, %d)", x1, y1, x2, y2)
    except Exception as exc:
        log.warning("Failed to save ROI config: %s", exc)


# Apply saved ROI at import time so the rest of the module sees it.
_saved = _load_roi_config()
if _saved is not None:
    SCAN_ROI = _saved
    log.info("Loaded scan ROI from config: %s", SCAN_ROI)

# ══════════════════════════════════════════════════════════════════════════════
#  SCAN ROI UTILITIES
# ══════════════════════════════════════════════════════════════════════════════

def get_scan_roi(raw_w: int, raw_h: int) -> Tuple[int, int, int, int]:
    """
    Return (x1, y1, x2, y2) in raw-frame pixel coords for the scan tray.
    Falls back to a centred square when SCAN_ROI is None.
    """
    if SCAN_ROI is not None:
        x1, y1, x2, y2 = SCAN_ROI
        x1 = max(0, min(x1, raw_w - 1))
        y1 = max(0, min(y1, raw_h - 1))
        x2 = max(x1 + 1, min(x2, raw_w))
        y2 = max(y1 + 1, min(y2, raw_h))
        return x1, y1, x2, y2
    side = min(raw_w, raw_h)
    x1   = (raw_w - side) // 2
    y1   = (raw_h - side) // 2
    return x1, y1, x1 + side, y1 + side


def apply_scan_roi(raw_frame: np.ndarray) -> np.ndarray:
    """
    Crop the raw camera frame to the scan ROI and resize while preserving
    the rectangular ROI aspect ratio. This prevents the calibrated view from
    looking stretched or rotated after Apply & Resume.
    """
    h, w = raw_frame.shape[:2]
    x1, y1, x2, y2 = get_scan_roi(w, h)

    cropped = raw_frame[y1:y2, x1:x2]

    if cropped.size == 0:
        log.error("Empty scan crop. SCAN_ROI may be out of bounds.")
        return np.zeros((SCAN_OUTPUT_H, SCAN_OUTPUT_W, 3), dtype=np.uint8)

    roi_h, roi_w = cropped.shape[:2]

    target_w = SCAN_OUTPUT_W
    target_h = int(target_w * roi_h / max(1, roi_w))

    # Keep height reasonable for the UI
    if target_h < 480:
        target_h = 480
    if target_h > 1000:
        target_h = 1000

    return cv2.resize(cropped, (target_w, target_h), interpolation=cv2.INTER_LINEAR)


def draw_roi_overlay(raw_frame: np.ndarray,
                     x1: int, y1: int, x2: int, y2: int) -> np.ndarray:
    """
    Return a copy of the raw frame with the ROI rectangle, corner arms,
    and a coordinate label drawn on it (used in calibration mode).
    """
    vis   = raw_frame.copy()
    color = (0, 220, 100)
    cv2.rectangle(vis, (x1, y1), (x2, y2), color, 3)
    arm = max(30, (x2 - x1) // 20)
    for cx, cy, sx, sy in [(x1, y1, 1, 1), (x2, y1, -1, 1),
                             (x1, y2, 1, -1), (x2, y2, -1, -1)]:
        cv2.line(vis, (cx, cy), (cx + sx * arm, cy),       color, 4, cv2.LINE_AA)
        cv2.line(vis, (cx, cy), (cx, cy + sy * arm),       color, 4, cv2.LINE_AA)
    w_roi, h_roi = x2 - x1, y2 - y1
    sq_warn = "" if abs(w_roi - h_roi) < 5 else "  ⚠ NOT SQUARE"
    label = f"  ROI ({x1},{y1})→({x2},{y2})  {w_roi}×{h_roi}px{sq_warn}  "
    ty    = max(y1 - 14, 30)
    cv2.putText(vis, label, (x1, ty), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (0, 0, 0),     4, cv2.LINE_AA)
    cv2.putText(vis, label, (x1, ty), cv2.FONT_HERSHEY_SIMPLEX, 0.65, color,          2, cv2.LINE_AA)
    return vis


def draw_viewfinder(scan_frame: np.ndarray) -> np.ndarray:
    """Draw subtle corner viewfinder marks on the SCAN_SIZE frame (live mode)."""
    h, w  = scan_frame.shape[:2]
    vis   = scan_frame.copy()
    color = (0, 180, 80)
    arm   = 36
    for cx, cy, sx, sy in [(0, 0, 1, 1), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)]:
        cv2.line(vis, (cx, cy), (cx + sx * arm, cy),  color, 2, cv2.LINE_AA)
        cv2.line(vis, (cx, cy), (cx, cy + sy * arm),  color, 2, cv2.LINE_AA)
    return vis

# ══════════════════════════════════════════════════════════════════════════════
#  STYLESHEET
# ══════════════════════════════════════════════════════════════════════════════
STYLESHEET = f"""
/* ── Globals ── */
QMainWindow, QWidget {{
    background: {C_BG};
    color: {C_TEXT};
    font-family: 'Segoe UI', 'SF Pro Display', sans-serif;
}}

/* ── Panels ── */
QWidget#leftPanel, QWidget#rightPanel {{
    background: {C_PANEL};
    border: 1px solid {C_BORDER};
    border-radius: 14px;
}}
QWidget#historyPanel {{
    background: {C_PANEL};
    border: 1px solid {C_BORDER};
    border-radius: 12px;
}}
QFrame#calibPanel {{
    background: #0A1830;
    border: 1px solid {C_WARN}55;
    border-radius: 10px;
}}

/* ── Header ── */
QWidget#headerBar {{
    background: qlineargradient(x1:0,y1:0,x2:1,y2:0,
        stop:0 #080E20, stop:0.4 #0B1630, stop:1 #080E20);
    border-bottom: 1px solid #1A2E50;
}}

/* ── Camera feed ── */
QLabel#cameraFeed {{
    background: #030712;
    border: 2px solid {C_BORDER};
    border-bottom: 3px solid #0A1830;
    border-right:  3px solid #0A1830;
    border-radius: 12px;
    color: {C_MUTED};
    font-size: 14px;
}}

/* ── Primary button ── */
QPushButton#captureBtn {{
    background: qlineargradient(x1:0,y1:0,x2:1,y2:0,
        stop:0 #0084A8, stop:0.5 #00B8D9, stop:1 #00D4F5);
    color: #04080F;
    font-size: 14px; font-weight: 700;
    border: none; border-radius: 24px;
    padding: 12px 28px; letter-spacing: 0.5px;
}}
QPushButton#captureBtn:hover {{
    background: qlineargradient(x1:0,y1:0,x2:1,y2:0, stop:0 #00B8D9, stop:1 #33E0FF);
}}
QPushButton#captureBtn:pressed  {{ background: #006A8A; }}
QPushButton#captureBtn:disabled {{ background: #132035; color: #2A3D5A; }}

/* ── OCR / green button ── */
QPushButton#ocrBtn {{
    background: qlineargradient(x1:0,y1:0,x2:1,y2:0, stop:0 #006A40, stop:1 #00C070);
    color: #04080F; font-size: 14px; font-weight: 700;
    border: none; border-radius: 24px; padding: 12px 28px;
}}
QPushButton#ocrBtn:hover   {{ background: qlineargradient(x1:0,y1:0,x2:1,y2:0, stop:0 #00A060, stop:1 #00E080); }}
QPushButton#ocrBtn:pressed {{ background: #004A30; }}
QPushButton#ocrBtn:disabled {{ background: #0A2018; color: #1A4030; }}

/* ── Ghost button ── */
QPushButton#ghostBtn {{
    background: transparent;
    color: {C_MUTED};
    font-size: 12px; font-weight: 600;
    border: 1px solid #1E3258; border-radius: 20px;
    padding: 8px 18px;
}}
QPushButton#ghostBtn:hover    {{ background: #1A2840; color: {C_TEXT}; border-color: #2E4A70; }}
QPushButton#ghostBtn:pressed  {{ background: #0E1A30; }}
QPushButton#ghostBtn:checked  {{ background: #1A2A10; color: {C_ACCENT2}; border-color: {C_ACCENT2}; }}

QPushButton#calibBtn {{
    background: transparent;
    color: {C_WARN};
    font-size: 11px; font-weight: 700;
    border: 1px solid {C_WARN}55; border-radius: 20px;
    padding: 8px 18px; letter-spacing: 0.4px;
}}
QPushButton#calibBtn:hover   {{ background: {C_WARN}18; }}
QPushButton#calibBtn:checked {{ background: {C_WARN}22; border-color: {C_WARN}; }}

QPushButton#clearBtn {{
    background: transparent; color: {C_ERR};
    font-size: 11px;
    border: 1px solid #3D1020; border-radius: 14px;
    padding: 5px 14px;
}}
QPushButton#clearBtn:hover {{ background: #1E0A12; border-color: {C_ERR}; }}

/* ── Calibration panel inner elements ── */
QSpinBox {{
    background: #0A1628; color: {C_TEXT};
    border: 1px solid {C_BORDER}; border-radius: 4px;
    padding: 3px 6px; font-size: 11px;
}}
QSpinBox:focus {{ border-color: {C_WARN}; }}

/* ── Labels ── */
QLabel#appTitle    {{ color: #E8EDF4; font-size: 20px; font-weight: 800; letter-spacing: 0.5px; }}
QLabel#appSubtitle {{ color: #2E4868; font-size: 10px; letter-spacing: 2px; }}
QLabel#sectionTitle {{ color: {C_ACCENT}; font-size: 10px; font-weight: 700; letter-spacing: 2px; }}
QLabel#statusLabel  {{ color: {C_MUTED}; font-size: 12px; }}
QLabel#counterLabel {{ color: {C_TEXT};  font-size: 26px; font-weight: 800; }}
QLabel#counterSub   {{ color: {C_MUTED}; font-size: 9px;  letter-spacing: 1.5px; }}

/* ── Scrollbars ── */
QScrollArea {{ background: transparent; border: none; }}
QScrollBar:vertical {{ background: {C_BG}; width: 5px; border-radius: 3px; }}
QScrollBar::handle:vertical {{ background: #1E3050; border-radius: 3px; min-height: 24px; }}
QScrollBar::handle:vertical:hover {{ background: {C_ACCENT}; }}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{ height: 0; }}

/* ── Status bar ── */
QStatusBar {{ background: #030610; color: #2A4060; font-size: 11px; border-top: 1px solid #0D1526; }}

/* ── Tabs ── */
QTabWidget::pane {{ border: none; background: transparent; }}
QTabBar::tab {{
    background: transparent; color: {C_MUTED};
    font-size: 12px; font-weight: 600;
    padding: 9px 22px; border-bottom: 2px solid transparent;
    margin-bottom: -1px;
}}
QTabBar::tab:selected {{ color: {C_ACCENT}; border-bottom: 2px solid {C_ACCENT}; }}
QTabBar::tab:hover    {{ color: #7AC8E0; }}

/* ── Progress bar ── */
QProgressBar {{
    background: #0A1628; border: none;
    border-radius: 3px; height: 5px; text-align: right;
}}
QProgressBar::chunk {{ border-radius: 3px; }}

/* ── Log view ── */
QTextEdit#logView {{
    background: #03070F; color: #2A7050;
    font-family: 'Cascadia Code', 'Fira Code', 'Courier New', monospace;
    font-size: 11px;
    border: 1px solid #0A1E10; border-radius: 8px;
    padding: 10px;
    selection-background-color: #1A4030;
}}
"""

# ══════════════════════════════════════════════════════════════════════════════
#  v3: POST-YOLO DUPLICATE SUPPRESSION
# ══════════════════════════════════════════════════════════════════════════════

def _box_iou(a: Tuple, b: Tuple) -> float:
    ax1, ay1, ax2, ay2 = a
    bx1, by1, bx2, by2 = b
    ix1, iy1 = max(ax1, bx1), max(ay1, by1)
    ix2, iy2 = min(ax2, bx2), min(ay2, by2)
    inter = max(0, ix2 - ix1) * max(0, iy2 - iy1)
    area_a = max(0, ax2 - ax1) * max(0, ay2 - ay1)
    area_b = max(0, bx2 - bx1) * max(0, by2 - by1)
    union  = area_a + area_b - inter
    return inter / union if union > 0 else 0.0


def deduplicate_detections(detections: List, iou_threshold: float = DEDUP_IOU_THRESHOLD) -> List:
    """
    Greedy confidence-descending IoU dedup.
    Collapses overlapping boxes that represent the same physical object.
    After dedup, restores top-to-bottom, left-to-right spatial order.
    """
    if not detections:
        return detections
    sorted_dets = sorted(detections, key=lambda d: float(d[2]), reverse=True)
    kept, suppressed = [], set()
    for i, det_i in enumerate(sorted_dets):
        if i in suppressed:
            continue
        kept.append(det_i)
        box_i = tuple(map(float, det_i[0]))
        for j in range(i + 1, len(sorted_dets)):
            if j not in suppressed and _box_iou(box_i, tuple(map(float, sorted_dets[j][0]))) >= iou_threshold:
                suppressed.add(j)
    kept.sort(key=lambda d: (float(d[0][1]), float(d[0][0])))
    return kept

# ══════════════════════════════════════════════════════════════════════════════
#  MATCHING ENGINE
# ══════════════════════════════════════════════════════════════════════════════

def _name_similarity(a: str, b: str) -> float:
    a, b = a.upper().strip(), b.upper().strip()
    if not a or not b:
        return 0.0
    char_sim = SequenceMatcher(None, a, b).ratio()
    wa, wb   = set(re.findall(r"\w+", a)), set(re.findall(r"\w+", b))
    word_sim = len(wa & wb) / max(len(wa), len(wb)) if wa and wb else 0.0
    fa, fb   = re.findall(r"[A-Z]+", a), re.findall(r"[A-Z]+", b)
    fw  = 0.10 if fa and fb and SequenceMatcher(None, fa[0], fb[0]).ratio() >= 0.80 else 0.0
    sub = 0.10 if (len(a) > 4 and a in b) or (len(b) > 4 and b in a) else 0.0
    return min(char_sim * 0.45 + word_sim * 0.35 + fw + sub, 1.0)


def _best_name_score(good_tokens: List[str], db_name: str) -> float:
    scores = [_name_similarity(t, db_name) for t in good_tokens]
    alpha  = [t for t in good_tokens if re.search(r"[A-Za-z]", t)]
    if len(alpha) > 1:
        scores.append(_name_similarity(" ".join(alpha),     db_name))
        scores.append(_name_similarity(" ".join(alpha[:2]), db_name))
    return max(scores) if scores else 0.0


def _extract_strengths(tokens: List[str]) -> Tuple[List[str], List[str]]:
    text = " ".join(tokens)
    with_units = [
        p.upper().replace(" ", "")
        for p in re.findall(
            r"\d+(?:\.\d+)?(?:\s*/\s*\d+(?:\.\d+)?)?\s*(?:mg|g|ml|mcg|iu|mmol)[/\w]*",
            text, re.IGNORECASE)
    ]
    bare_nums = re.findall(r"\b(\d{2,4})\b", text)
    return with_units, bare_nums


def _strength_score(with_units: List[str], bare_nums: List[str], db_strength: Any) -> float:
    if not db_strength or str(db_strength).upper() in ("NAN", "N/A", "", "NONE"):
        return 0.0
    db_s = str(db_strength).upper().replace(" ", "")
    db_n = set(re.findall(r"\d+(?:\.\d+)?", db_s))
    best = 0.0
    for s in with_units:
        if s == db_s:
            return 1.0
        if set(re.findall(r"\d+(?:\.\d+)?", s)) & db_n:
            best = max(best, 0.85)
        best = max(best, SequenceMatcher(None, s, db_s).ratio())
    if best < 0.50:
        for n in bare_nums:
            if n in db_n:
                best = max(best, 0.70)
    return best


def match_medicine(db: Optional[pd.DataFrame],
                   ocr_items: List[Dict]) -> Optional[Dict[str, Any]]:
    if db is None or not ocr_items:
        return None
    good = [
        t["text"] for t in ocr_items
        if t["score"] >= OCR_MIN_CONF
        and sum(c.isalpha() for c in t["text"]) >= OCR_MIN_LETTERS
    ]
    all_tokens = [t["text"] for t in ocr_items]
    with_units, bare_nums = _extract_strengths(all_tokens)
    if not good:
        return None

    shortlist = [
        (idx, _best_name_score(good, row["_mn"]))
        for idx, row in db.iterrows()
        if _best_name_score(good, row["_mn"]) >= NAME_THRESHOLD
    ]
    if not shortlist:
        return None

    scored = sorted(
        [
            (ns + STRENGTH_BOOST * _strength_score(with_units, bare_nums, db.loc[idx]["_str"]),
             ns,
             _strength_score(with_units, bare_nums, db.loc[idx]["_str"]),
             idx)
            for idx, ns in shortlist
        ],
        key=lambda x: x[0], reverse=True,
    )
    tot, ns, ss, win = scored[0]
    w = db.loc[win]
    return {
        "match_name":      w.get("match_name",      "N/A"),
        "brand_name":      w.get("brand_name",       "N/A"),
        "full_brand_name": w.get("full_brand_name",  "N/A"),
        "mal_number":      w.get("mal_number",       "N/A"),
        "generic_name":    w.get("generic_name",     "N/A"),
        "strength":        w.get("strength",         "N/A"),
        "dosage_form":     w.get("dosage_form",      "N/A"),
        "category":        w.get("category",         "N/A"),
        "unit":            w.get("unit",             "N/A"),
        "item_code":       w.get("item_code",        "N/A"),
        "name_score":      round(ns,  3),
        "strength_score":  round(ss,  3),
        "total_score":     round(tot, 3),
        "shortlist_count": len(shortlist),
    }

# ══════════════════════════════════════════════════════════════════════════════
#  OCR PREPROCESSING  (fast / full variants)
# ══════════════════════════════════════════════════════════════════════════════

def _base_upscale(roi: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY) if len(roi.shape) == 3 else roi
    h, w = roi.shape[:2]
    if max(h, w) < OCR_UPSCALE_TARGET:
        scale   = max(2, OCR_UPSCALE_TARGET // max(h, w))
        roi_up  = cv2.resize(roi,  (w * scale, h * scale), interpolation=cv2.INTER_CUBIC)
        gray_up = cv2.resize(gray, (w * scale, h * scale), interpolation=cv2.INTER_CUBIC)
    else:
        roi_up, gray_up = roi.copy(), gray.copy()
    return roi_up, gray_up


def _fast_variants(roi: np.ndarray) -> List[Tuple[str, np.ndarray]]:
    if roi is None or roi.size == 0:
        return []
    up, gray_up = _base_upscale(roi)
    clahe   = cv2.createCLAHE(clipLimit=3.5, tileGridSize=(8, 8))
    cl_gray = clahe.apply(gray_up)
    return [
        ("original", up),
        ("clahe",    cv2.cvtColor(cl_gray, cv2.COLOR_GRAY2BGR)),
    ]


def _full_variants(roi: np.ndarray) -> List[Tuple[str, np.ndarray]]:
    if roi is None or roi.size == 0:
        return []
    up, gray_up = _base_upscale(roi)
    clahe    = cv2.createCLAHE(clipLimit=3.5, tileGridSize=(8, 8))
    cl_gray  = clahe.apply(gray_up)
    blur     = cv2.GaussianBlur(gray_up, (3, 3), 0)
    adaptive = cv2.adaptiveThreshold(blur, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 15, 8)
    _, otsu  = cv2.threshold(blur, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    kernel   = np.array([[0, -1, 0], [-1, 5, -1], [0, -1, 0]], dtype=np.float32)
    sharp    = cv2.filter2D(cl_gray, -1, kernel)
    inv      = cv2.bitwise_not(adaptive)
    return [
        ("adaptive_bw",  cv2.cvtColor(adaptive, cv2.COLOR_GRAY2BGR)),
        ("otsu",         cv2.cvtColor(otsu,     cv2.COLOR_GRAY2BGR)),
        ("sharp_clahe",  cv2.cvtColor(sharp,    cv2.COLOR_GRAY2BGR)),
        ("inv_adaptive", cv2.cvtColor(inv,       cv2.COLOR_GRAY2BGR)),
    ]


def _run_variants(ocr_engine,
                  variants: List[Tuple[str, np.ndarray]],
                  existing: Optional[Dict] = None) -> Tuple[List[Dict], Dict]:
    best_by_text: Dict[str, Dict] = dict(existing) if existing else {}
    for label, img in variants:
        if img is None or img.size == 0:
            continue
        try:
            raw = ocr_engine.ocr(img)
        except Exception as exc:
            log.warning("OCR variant '%s' failed: %s", label, exc)
            continue
        for block in (raw or []):
            items_raw: List[Dict] = []
            if isinstance(block, dict) and "rec_texts" in block:
                bxs = block.get("dt_polys") or block.get("rec_polys", [])
                for bx, tx, sc in zip(bxs, block["rec_texts"], block["rec_scores"]):
                    h_ = abs(bx[2][1] - bx[0][1]) if bx is not None else 50
                    items_raw.append({"text": str(tx), "score": float(sc), "height": float(h_), "strategy": label})
            elif block:
                for line in block:
                    try:
                        bx   = line[0]; info = line[1]
                        tx   = info[0] if isinstance(info, (list, tuple)) else str(info)
                        sc   = float(info[1]) if isinstance(info, (list, tuple)) and len(info) > 1 else 1.0
                        h_   = abs(bx[2][1] - bx[0][1]) if isinstance(bx, (list, np.ndarray)) else 50
                        items_raw.append({"text": str(tx), "score": sc, "height": float(h_), "strategy": label})
                    except Exception as exc:
                        log.debug("OCR line parse error in '%s': %s", label, exc)
                        continue
            for item in items_raw:
                key = item["text"].upper().strip()
                if not key:
                    continue
                if key not in best_by_text or item["score"] > best_by_text[key]["score"]:
                    best_by_text[key] = item
    merged = sorted(best_by_text.values(), key=lambda x: x["height"], reverse=True)
    return merged, best_by_text


def _ocr_quality(items: List[Dict]) -> Tuple[float, int]:
    good = [t for t in items
            if t["score"] >= OCR_MIN_CONF
            and sum(c.isalpha() for c in t["text"]) >= OCR_MIN_LETTERS]
    if not good:
        return 0.0, 0
    return sum(t["score"] for t in good) / len(good), len(good)


def run_ocr_hybrid(ocr_engine,
                   roi: np.ndarray,
                   db: Optional[pd.DataFrame] = None,
                   log_fn=None) -> Tuple[List[Dict], str]:
    """
    Hybrid OCR dispatcher.
    Returns (ocr_items, mode_used)   mode in {"fast", "full", "fast+full"}.
    """
    def _log(msg: str) -> None:
        if log_fn:
            log_fn(msg)

    fast_vars      = _fast_variants(roi)
    items, pool    = _run_variants(ocr_engine, fast_vars)

    if not OCR_FAST_MODE:
        _log("   📖 Full OCR mode (fast disabled) — running all 6 variants")
        items, _ = _run_variants(ocr_engine, _full_variants(roi), pool)
        return items, "full"

    quality, good_n = _ocr_quality(items)
    _log(f"   ⚡ Fast OCR: {len(items)} tokens, {good_n} high-conf, quality={quality:.2f}")

    if db is not None:
        fast_match = match_medicine(db, items)
        if fast_match:
            _log(f"   ✅ DB match on fast OCR: {fast_match['full_brand_name']} — skipping full")
            return items, "fast"
        reason = (
            f"quality={quality:.2f} but no DB match"
            if quality >= OCR_HYBRID_QUALITY_THRESHOLD
            else f"quality={quality:.2f} < threshold and no DB match"
        )
        _log(f"   🔄 Escalating to full OCR ({reason})")
    else:
        if quality >= OCR_HYBRID_QUALITY_THRESHOLD and good_n >= OCR_HYBRID_MIN_GOOD_TOKENS:
            _log(f"   ✅ Fast quality sufficient ({quality:.2f}, {good_n} tokens)")
            return items, "fast"
        _log(f"   🔄 Low fast quality ({quality:.2f}) — escalating")

    items, _ = _run_variants(ocr_engine, _full_variants(roi), pool)
    q2, g2   = _ocr_quality(items)
    _log(f"   📊 Full OCR: {len(items)} tokens, {g2} high-conf, quality={q2:.2f}")
    return items, "fast+full"

# ══════════════════════════════════════════════════════════════════════════════
#  ORIENTED BOUNDING BOX
# ══════════════════════════════════════════════════════════════════════════════

def fit_oriented_box(frame: np.ndarray,
                     x1: int, y1: int, x2: int, y2: int) -> Tuple[np.ndarray, float]:
    fh, fw = frame.shape[:2]
    pad = 6
    rx1 = max(0, x1 - pad);  ry1 = max(0, y1 - pad)
    rx2 = min(fw, x2 + pad); ry2 = min(fh, y2 + pad)
    roi = frame[ry1:ry2, rx1:rx2]
    if roi.size == 0:
        return _axis_aligned_pts(x1, y1, x2, y2), 0.0

    gray  = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    eq    = clahe.apply(gray)
    blur  = cv2.GaussianBlur(eq, (5, 5), 0)
    edges = cv2.Canny(blur, 30, 90)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (9, 9))
    closed = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, kernel, iterations=2)
    cnts, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not cnts:
        return _axis_aligned_pts(x1, y1, x2, y2), 0.0

    roi_area = (rx2 - rx1) * (ry2 - ry1)
    big = [c for c in cnts if cv2.contourArea(c) >= roi_area * 0.10] or list(cnts)
    merged = np.vstack(big)
    rect   = cv2.minAreaRect(merged)
    pts    = cv2.boxPoints(rect).astype(np.int32)
    pts[:, 0] += rx1; pts[:, 1] += ry1

    ob_x1, ob_y1 = pts[:, 0].min(), pts[:, 1].min()
    ob_x2, ob_y2 = pts[:, 0].max(), pts[:, 1].max()
    ob_area   = max(1, (ob_x2 - ob_x1) * (ob_y2 - ob_y1))
    yolo_area = max(1, (x2 - x1) * (y2 - y1))

    if ob_area < yolo_area * 0.25 or ob_area > yolo_area * 2.8:
        return _axis_aligned_pts(x1, y1, x2, y2), 0.0
    return pts, float(rect[-1])


def _axis_aligned_pts(x1: int, y1: int, x2: int, y2: int) -> np.ndarray:
    return np.array([[x1, y2], [x2, y2], [x2, y1], [x1, y1]], dtype=np.int32)


def draw_obb(img: np.ndarray, pts: np.ndarray, color: Tuple, thickness: int = 2) -> None:
    cv2.polylines(img, [pts.reshape(-1, 1, 2)], isClosed=True,
                  color=color, thickness=thickness, lineType=cv2.LINE_AA)


def label_obb(img: np.ndarray, pts: np.ndarray, text: str, color: Tuple) -> None:
    if not text:
        return
    order  = np.argsort(pts[:, 1])
    top2   = pts[order[:2]]
    anchor = top2[np.argmin(top2[:, 0])]
    ax, ay = int(anchor[0]), int(anchor[1])

    font       = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.46
    thickness  = 1
    (tw, th), _ = cv2.getTextSize(text, font, font_scale, thickness)
    pad = 4
    bx1 = max(0, ax);              by1 = max(0, ay - th - pad * 2)
    bx2 = min(img.shape[1]-1, ax + tw + pad * 2); by2 = max(0, ay)

    overlay = img.copy()
    cv2.rectangle(overlay, (bx1, by1), (bx2, by2), color, -1)
    cv2.addWeighted(overlay, 0.80, img, 0.20, 0, img)
    cv2.putText(img, text, (bx1 + pad, by2 - pad),
                font, font_scale, (15, 15, 25), thickness, cv2.LINE_AA)

# ══════════════════════════════════════════════════════════════════════════════
#  THREADS
# ══════════════════════════════════════════════════════════════════════════════

class CameraThread(QThread):
    """
    Captures raw frames from the camera.
    Auto-negotiates the best resolution from CAMERA_RESOLUTION_CANDIDATES.
    Emits raw frames; the main thread applies the scan ROI crop.
    """
    frame_ready = pyqtSignal(np.ndarray)
    status      = pyqtSignal(str)

    def __init__(self):
        super().__init__()
        self._run = True

    def _fix_orientation(self, frame: np.ndarray) -> np.ndarray:
        if CAMERA_ROTATE == 90:
            frame = cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
        elif CAMERA_ROTATE == 180:
            frame = cv2.rotate(frame, cv2.ROTATE_180)
        elif CAMERA_ROTATE == 270:
            frame = cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
        if CAMERA_FLIP_HORIZONTAL:
            frame = cv2.flip(frame, 1)
        if CAMERA_FLIP_VERTICAL:
            frame = cv2.flip(frame, 0)
        return frame

    def run(self):
        log.info("[Camera] Attempting to open camera. Configured index: %s, Backend: %s", CAMERA_INDEX, CAMERA_BACKEND)
        cap = None
        opened_index = -1

        # First try the configured index
        try:
            temp_cap = (cv2.VideoCapture(CAMERA_INDEX) if CAMERA_BACKEND is None
                        else cv2.VideoCapture(CAMERA_INDEX, CAMERA_BACKEND))
            if temp_cap.isOpened():
                cap = temp_cap
                opened_index = CAMERA_INDEX
                log.info("[Camera] Successfully opened configured camera index: %d", opened_index)
        except Exception as e:
            log.warning("[Camera] Failed to open configured camera index %s: %s", CAMERA_INDEX, e)

        # If configured index fails, probe 0-5
        if cap is None or not cap.isOpened():
            log.info("[Camera] Configured camera index failed or not opened. Probing indices 0-5...")
            for idx in range(6):
                if idx == CAMERA_INDEX:
                    continue  # Already tried
                try:
                    log.info("[Camera] Probing index: %d", idx)
                    temp_cap = (cv2.VideoCapture(idx) if CAMERA_BACKEND is None
                                else cv2.VideoCapture(idx, CAMERA_BACKEND))
                    if temp_cap.isOpened():
                        cap = temp_cap
                        opened_index = idx
                        log.info("[Camera] Successfully opened probed camera index: %d", opened_index)
                        break
                    else:
                        temp_cap.release()
                except Exception as e:
                    log.debug("[Camera] Probe failed for index %d: %s", idx, e)

        if cap is None or not cap.isOpened():
            log.error("[Camera] All camera indices (configured + probed 0-5) failed to open.")
            self.status.emit("❌  Cannot open camera. Connect it and retry.")
            return

        # ── Negotiate best resolution ────────────────────────────────────────
        actual_w = actual_h = 0
        for target_w, target_h in CAMERA_RESOLUTION_CANDIDATES:
            cap.set(cv2.CAP_PROP_FRAME_WIDTH,  target_w)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, target_h)
            # Flush buffer so get() returns the new resolution
            for _ in range(3):
                cap.grab()
            aw = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            ah = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            if aw >= target_w * 0.95 and ah >= target_h * 0.95:
                actual_w, actual_h = aw, ah
                self.status.emit(
                    f"ℹ️  Camera locked at {aw}×{ah}  "
                    f"(target {target_w}×{target_h})  "
                    f"— scan ROI: {get_scan_roi(aw, ah)}"
                )
                break
        else:
            actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            self.status.emit(
                f"⚠️  Could not lock preferred resolution. "
                f"Camera is at {actual_w}×{actual_h}."
            )

        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

        while self._run:
            if not cap.grab():
                self.status.emit("⚠️  Frame grab failed — camera disconnected?")
                break
            ret, frame = cap.retrieve()
            if not ret:
                continue
            self.frame_ready.emit(self._fix_orientation(frame))
            self.msleep(30)
        cap.release()

    def stop(self):
        self._run = False
        self.wait()


class YOLODetectThread(QThread):
    """Runs YOLO on a scan frame (SCAN_SIZE × SCAN_SIZE)."""
    detections_ready = pyqtSignal(list)
    log_msg          = pyqtSignal(str)

    def __init__(self, scan_frame: np.ndarray, yolo_model):
        super().__init__()
        self.frame = scan_frame
        self.yolo  = yolo_model

    def run(self):
        self.log_msg.emit("🔍 Running high-accuracy YOLO on frozen scan frame…")
        try:
            res   = self.yolo.predict(
                source=self.frame, conf=YOLO_CAPTURE_CONF,
                iou=YOLO_CAPTURE_IOU, imgsz=YOLO_CAPTURE_IMGSZ,
                augment=YOLO_CAPTURE_AUGMENT, max_det=YOLO_CAPTURE_MAX_DET,
                save=False, verbose=False)
            boxes = res[0].boxes.xyxy.cpu().numpy()
            clss  = res[0].boxes.cls.cpu().numpy()
            confs = res[0].boxes.conf.cpu().numpy()
            raw_dets = list(zip(boxes, clss, confs))

            before_n = len(raw_dets)
            dets     = deduplicate_detections(raw_dets, DEDUP_IOU_THRESHOLD)
            after_n  = len(dets)
            if before_n != after_n:
                self.log_msg.emit(
                    f"   🧹 Dedup: {before_n} → {after_n} detections "
                    f"(removed {before_n - after_n} overlapping, IoU≥{DEDUP_IOU_THRESHOLD})"
                )
        except Exception as exc:
            self.log_msg.emit(f"❌ YOLO error: {exc}")
            log.exception("YOLO thread error")
            dets = []
        self.log_msg.emit(f"✅ YOLO: {len(dets)} object(s) after dedup")
        self.detections_ready.emit(dets)


class OCROnlyThread(QThread):
    """Runs OCR on YOLO-detected regions within the scan frame."""
    result_ready = pyqtSignal(list)
    progress     = pyqtSignal(int, int)
    log_msg      = pyqtSignal(str)

    def __init__(self, scan_frame: np.ndarray, detections: List,
                 ocr_engine, db: Optional[pd.DataFrame],
                 prev_results: Optional[List] = None):
        super().__init__()
        self.frame      = scan_frame
        self.detections = detections
        self.ocr        = ocr_engine
        self.db         = db
        self._prev      = {r["det_idx"]: r for r in (prev_results or [])}

    def run(self):
        results: List[Dict] = []
        n = len(self.detections)

        has_top = any(CLASS_NAMES.get(int(c)) == "Strip Top"  for _, c, _ in self.detections)
        has_med = any(CLASS_NAMES.get(int(c)) == "Medicine"   for _, c, _ in self.detections)
        if has_top and not has_med:
            self.log_msg.emit("⚠️  Strip Top detected — flip strip to show back side for better OCR.")

        for i, (box, cls, conf) in enumerate(self.detections):
            self.progress.emit(i + 1, n)
            nm = CLASS_NAMES.get(int(cls), "?")
            self.log_msg.emit(f"\n[{i+1}/{n}] ▶ {nm}  (YOLO conf={conf:.0%})")

            x1, y1, x2, y2 = map(int, box)
            h, w = self.frame.shape[:2]
            pad  = OCR_PAD
            roi  = self.frame[max(0, y1-pad):min(h, y2+pad),
                               max(0, x1-pad):min(w, x2+pad)]

            # OCR_SKIP_STRIP_TOP is now the actual control flag
            if OCR_SKIP_STRIP_TOP and nm == "Strip Top":
                self.log_msg.emit("   ⏭  Strip Top skipped (OCR_SKIP_STRIP_TOP=True)")
                ocr_hits, mode = [], "skipped"
                match          = None
            else:
                ocr_hits, mode = run_ocr_hybrid(
                    self.ocr, roi, self.db,
                    log_fn=lambda m: self.log_msg.emit(m))
                self.log_msg.emit(f"   📝 {len(ocr_hits)} merged tokens  [mode={mode}]")
                match = match_medicine(self.db, ocr_hits)

            if match:
                self.log_msg.emit(
                    f"   ✅ {match['full_brand_name']}  "
                    f"name={match['name_score']:.2f}  str={match['strength_score']:.2f}")
            else:
                self.log_msg.emit("   ❌ No DB match")

            prev = self._prev.get(i, {})
            results.append({
                "det_idx":    i,
                "class_name": nm,
                "conf":       float(conf),
                "box":        [int(x1), int(y1), int(x2), int(y2)],
                "obb_pts":    prev.get("obb_pts",  _axis_aligned_pts(x1, y1, x2, y2)),
                "obb_angle":  prev.get("obb_angle", 0.0),
                "ocr_hits":   ocr_hits,
                "ocr_mode":   mode,
                "match":      match,
            })

        self.result_ready.emit(results)

# ══════════════════════════════════════════════════════════════════════════════
#  UI WIDGETS
# ══════════════════════════════════════════════════════════════════════════════

class PulsingDot(QWidget):
    def __init__(self, color: str = C_ACCENT, parent=None):
        super().__init__(parent)
        self.color = QColor(color); self._alpha = 255; self._step = -10
        self.setFixedSize(10, 10)
        t = QTimer(self); t.timeout.connect(self._pulse); t.start(35)

    def _pulse(self):
        self._alpha = max(60, min(255, self._alpha + self._step))
        if self._alpha <= 60 or self._alpha >= 255:
            self._step *= -1
        self.update()

    def paintEvent(self, _):
        p = QPainter(self); p.setRenderHint(QPainter.Antialiasing)
        c = QColor(self.color); c.setAlpha(self._alpha)
        p.setBrush(QBrush(c)); p.setPen(Qt.NoPen)
        p.drawEllipse(0, 0, 10, 10)


class ModeChip(QLabel):
    MODES: Dict[str, Tuple[str, str]] = {
        "live":      (C_ACCENT,  "● LIVE"),
        "detecting": (C_WARN,    "⏳ YOLO"),
        "detected":  ("#AA80FF", "▣ FROZEN"),
        "ocr":       (C_ACCENT2, "⟳ OCR"),
        "done":      (C_ACCENT2, "✓ DONE"),
        "calibrate": (C_WARN,    "⊞ CALIBRATE"),
    }

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedHeight(26)
        self.set_mode("live")

    def set_mode(self, mode: str):
        color, text = self.MODES.get(mode, (C_MUTED, mode.upper()))
        self.setText(f"  {text}  ")
        self.setStyleSheet(f"""
            background: {color}22; color: {color};
            border: 1px solid {color}55;
            border-radius: 13px;
            font-size: 11px; font-weight: 700; letter-spacing: 1px;
            padding: 0 4px;
        """)


class OCRModeBadge(QLabel):
    COLORS: Dict[str, str] = {
        "fast": C_ACCENT2, "fast+full": C_WARN, "full": C_ERR, "skipped": C_MUTED,
    }

    def __init__(self, mode: str = "fast", parent=None):
        super().__init__(parent)
        c = self.COLORS.get(mode, C_MUTED)
        self.setText(f"  OCR: {mode}  ")
        self.setStyleSheet(f"""
            background:{c}18; color:{c};
            border:1px solid {c}44; border-radius:8px;
            font-size:9px; font-weight:700; padding:2px 4px; letter-spacing:0.5px;
        """)


class ConfidenceBar(QProgressBar):
    def __init__(self, value: float, parent=None):
        super().__init__(parent)
        self.setRange(0, 100)
        self.setValue(int(max(0.0, min(1.0, value)) * 100))
        self.setTextVisible(False); self.setFixedHeight(4)
        color = C_ACCENT2 if value >= 0.85 else C_WARN if value >= 0.65 else C_ERR
        self.setStyleSheet(f"""
            QProgressBar {{ background:#111E35; border:none; border-radius:2px; }}
            QProgressBar::chunk {{ background:{color}; border-radius:2px; }}
        """)


class MedicineCard(QFrame):
    def __init__(self, result: Dict, parent=None):
        super().__init__(parent)
        self.setObjectName("medCard")
        m    = result.get("match")
        cat  = m["category"] if m else "Unknown"
        c    = CATEGORY_COLORS.get(cat, C_MUTED)
        mode = result.get("ocr_mode", "")

        self.setStyleSheet(f"""
            QFrame#medCard {{
                background: {C_CARD}; border: 1px solid {c}25;
                border-left: 3px solid {c}; border-radius: 12px;
            }}
            QFrame#medCard:hover {{
                background: #121E38; border: 1px solid {c}44;
                border-left: 3px solid {c};
            }}
        """)
        lay = QVBoxLayout(self)
        lay.setContentsMargins(16, 14, 16, 14); lay.setSpacing(10)

        if m:
            top = QHBoxLayout(); top.setSpacing(12)
            icon_lbl = QLabel(DOSAGE_ICONS.get(m["dosage_form"], "💊"))
            icon_lbl.setFont(QFont("Segoe UI Emoji", 24))
            icon_lbl.setFixedSize(42, 42); icon_lbl.setAlignment(Qt.AlignCenter)
            icon_lbl.setStyleSheet(f"background:{c}14; border-radius:21px;")
            top.addWidget(icon_lbl)

            name_col = QVBoxLayout(); name_col.setSpacing(3)
            full_lbl = QLabel(str(m["full_brand_name"]))
            full_lbl.setWordWrap(True)
            full_lbl.setStyleSheet("color:#E8EDF4; font-size:15px; font-weight:700;")
            name_col.addWidget(full_lbl)
            gen_lbl = QLabel(str(m["generic_name"]))
            gen_lbl.setStyleSheet(f"color:{C_MUTED}; font-size:10px;")
            name_col.addWidget(gen_lbl)
            top.addLayout(name_col, 1)

            badges = QVBoxLayout(); badges.setSpacing(4); badges.setAlignment(Qt.AlignTop | Qt.AlignRight)
            cat_b = QLabel(f"  {cat}  ")
            cat_b.setStyleSheet(f"""
                background:{c}20; color:{c}; border:1px solid {c}60;
                border-radius:10px; font-size:9px; font-weight:700; padding:3px 6px;
            """)
            badges.addWidget(cat_b)
            if mode:
                badges.addWidget(OCRModeBadge(mode))
            top.addLayout(badges)
            lay.addLayout(top)

            div = QFrame(); div.setFrameShape(QFrame.HLine)
            div.setStyleSheet(f"background:{C_BORDER}; border:none; max-height:1px;")
            lay.addWidget(div)

            grid = QGridLayout(); grid.setSpacing(10)
            for col, (label, val) in enumerate([
                ("STRENGTH",  m["strength"]),
                ("FORM",      m["dosage_form"]),
                ("MAL NO.",   m.get("mal_number", "N/A")),
                ("ITEM CODE", m["item_code"]),
            ]):
                cw = QVBoxLayout(); cw.setSpacing(2)
                l  = QLabel(label)
                l.setStyleSheet(f"color:{C_MUTED}; font-size:8px; font-weight:700; letter-spacing:1.2px;")
                v  = QLabel(str(val)); v.setWordWrap(True)
                v.setStyleSheet("color:#B0C8E8; font-size:11px; font-weight:600;")
                cw.addWidget(l); cw.addWidget(v)
                grid.addLayout(cw, 0, col)
            lay.addLayout(grid)

            sc_row = QHBoxLayout(); sc_row.setSpacing(16)
            for lbl, val in [
                ("NAME",     m["name_score"]),
                ("STRENGTH", m["strength_score"]),
                ("TOTAL",    min(1.0, m["total_score"] / 1.3)),
            ]:
                col = QVBoxLayout(); col.setSpacing(4)
                sl  = QLabel(f"{lbl}  {val:.0%}")
                sl.setStyleSheet(f"color:{C_MUTED}; font-size:8px; font-weight:700; letter-spacing:0.8px;")
                col.addWidget(sl); col.addWidget(ConfidenceBar(val))
                sc_row.addLayout(col)
            lay.addLayout(sc_row)

        else:
            nm   = result["class_name"]
            miss = QHBoxLayout()
            icon = QLabel("⚠️"); icon.setFont(QFont("Segoe UI Emoji", 18))
            miss.addWidget(icon)
            col  = QVBoxLayout(); col.setSpacing(3)
            ttl  = QLabel("No match found")
            ttl.setStyleSheet("color:#C05060; font-size:13px; font-weight:700;")
            sub  = QLabel(f"{nm}  ·  YOLO conf {result['conf']:.0%}")
            sub.setStyleSheet(f"color:{C_MUTED}; font-size:10px;")
            col.addWidget(ttl); col.addWidget(sub)
            miss.addLayout(col); miss.addStretch()
            if mode:
                miss.addWidget(OCRModeBadge(mode))
            lay.addLayout(miss)
            if result.get("ocr_hits"):
                sample = ", ".join(t["text"] for t in result["ocr_hits"][:6])
                hint = QLabel(f"OCR tokens: {sample}")
                hint.setWordWrap(True)
                hint.setStyleSheet("color:#6A3A48; font-size:10px; padding-top:4px;")
                lay.addWidget(hint)


class HistoryRow(QFrame):
    def __init__(self, ts: str, results: List, parent=None):
        super().__init__(parent)
        matches = [r["match"] for r in results if r.get("match")]
        self.setStyleSheet(f"""
            QFrame {{ background:#0B1525; border:1px solid {C_BORDER}; border-radius:8px; }}
            QFrame:hover {{ background:#101E35; border-color:#233050; }}
        """)
        lay = QHBoxLayout(self); lay.setContentsMargins(12, 8, 12, 8)
        ts_lbl = QLabel(ts)
        ts_lbl.setStyleSheet(f"color:{C_MUTED}; font-size:10px; min-width:62px;")
        lay.addWidget(ts_lbl)
        if matches:
            names = QLabel(" · ".join(str(m["full_brand_name"]) for m in matches[:3]))
            names.setWordWrap(True)
            names.setStyleSheet("color:#7AACCE; font-size:11px; font-weight:600;")
            lay.addWidget(names, 1)
            cnt = QLabel(f"{len(matches)} match{'es' if len(matches) > 1 else ''}")
            cnt.setStyleSheet(f"color:{C_ACCENT}; font-size:10px; font-weight:700;")
            lay.addWidget(cnt)
        else:
            no_m = QLabel("No matches")
            no_m.setStyleSheet("color:#7A4050; font-size:11px;")
            lay.addWidget(no_m); lay.addStretch()

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN WINDOW
# ══════════════════════════════════════════════════════════════════════════════

class MedScanPro(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MedScan Pro")
        self.setMinimumSize(1200, 750)
        self.resize(1460, 900)

        self._load_database()
        # Placeholders for model state to prevent errors before load finishes
        self.yolo = None
        self.ocr = None
        self._yolo_ok = False
        self._ocr_ok = False

        # State
        self._current_raw_frame : Optional[np.ndarray] = None
        self._current_scan_frame: Optional[np.ndarray] = None
        self._captured_frame    : Optional[np.ndarray] = None   # always scan-space
        self._captured_dets     : List = []
        self._mode              : str  = "live"
        self._calibrate_mode    : bool = False
        self._scan_count        : int  = 0
        self._scan_running      : bool = False
        self._last_results      : List = []
        self._history           : List = []
        self._inventory_ok      : bool = False

        # Strong refs to active threads (prevents GC mid-run)
        self._yolo_thread : Optional[QThread] = None
        self._ocr_thread  : Optional[QThread] = None

        if INVENTORY_SYNC_AVAILABLE:
            try:
                init_local_db()
                self._inventory_ok = True
            except Exception as exc:
                log.error("Inventory DB init failed: %s", exc)

        self._build_ui()
        self._setup_shortcuts()
        self._start_camera()

        if self._inventory_ok and INVENTORY_SYNC_AVAILABLE:
            self._sync_timer = QTimer(self)
            self._sync_timer.timeout.connect(self._auto_sync_pending)
            self._sync_timer.start(30_000)
            QTimer.singleShot(2_000, self._auto_sync_pending)

        self._set_mode("live")
        self.status_bar.showMessage(
            "🟢  Ready — Space/Enter to capture + YOLO  ·  Enter after boxes for OCR  ·  R to reset  ·  ⊞ Calibrate to align scan area"
        )
        # Delayed model loading (after window renders and event loop starts)
        QTimer.singleShot(100, self._load_models)

    # ── Auto-sync ─────────────────────────────────────────────────────────────

    def _auto_sync_pending(self):
        if not self._inventory_ok or not INVENTORY_SYNC_AVAILABLE:
            return
        if getattr(self, "_sync_in_progress", False):
            return
        self._sync_in_progress = True
        try:
            result = sync_unsynced_transactions()
            n = int(result.get("synced_count", 0) or 0)
            if result.get("ok") and n > 0:
                self.status_bar.showMessage(f"☁️  Auto-sync: {n} pending transaction(s) uploaded.")
                if hasattr(self, "log_view"):
                    self.log_view.append(
                        f"<br><span style='color:{C_ACCENT2}'>☁️ AUTO-SYNC: {n} transaction(s) uploaded.</span>")
            elif not result.get("ok"):
                log.debug("Auto-sync pending: %s", result)
        except Exception as exc:
            log.warning("Auto-sync error: %s", exc)
        finally:
            self._sync_in_progress = False

    # ── Database & models ──────────────────────────────────────────────────────

    def _find_database_path(self) -> str:
        for p in DATABASE_CANDIDATES:
            if os.path.exists(p):
                return p
        log.warning("No database CSV found; tried: %s", DATABASE_CANDIDATES)
        return DATABASE_CANDIDATES[0]

    def _load_database(self):
        self.db   = None
        self._db_ok = False
        self.database_path = self._find_database_path()
        try:
            for enc in ("utf-8", "latin-1", "cp1252"):
                try:
                    self.db = pd.read_csv(self.database_path, encoding=enc)
                    break
                except UnicodeDecodeError:
                    continue
            if self.db is None:
                raise ValueError("Could not decode CSV with any supported encoding.")
            required = ["match_name", "strength", "full_brand_name"]
            missing  = [c for c in required if c not in self.db.columns]
            if missing:
                raise ValueError(f"CSV missing required columns: {missing}")
            self.db["_mn"]  = self.db["match_name"].astype(str).str.upper().str.strip()
            self.db["_str"] = self.db["strength"].astype(str).str.upper().str.strip()
            self._db_ok = True
            log.info("Database loaded: %d rows from %s", len(self.db), self.database_path)
        except Exception as exc:
            log.error("Database load failed: %s", exc)

    def _load_models(self):
        import traceback
        self.status_bar.showMessage("⏳ Loading AI models (YOLO & PaddleOCR)…")
        log.info("[Model Loader] Starting model initialization on thread: %s", QThread.currentThread())
        
        # Diagnostic logging
        log.info("[Model Loader] KMP_DUPLICATE_LIB_OK: %s", os.environ.get("KMP_DUPLICATE_LIB_OK"))
        log.info("[Model Loader] sys.executable: %s", sys.executable)
        log.info("[Model Loader] sys.path: %s", sys.path[:5])
        log.info("[Model Loader] os.environ PATH: %s", os.environ.get("PATH", ""))
        
        # Check for loaded/imported packages
        log.info("[Model Loader] PyQt5 imported: %s", "PyQt5" in sys.modules)
        log.info("[Model Loader] cv2 imported: %s", "cv2" in sys.modules)
        log.info("[Model Loader] torch imported: %s", "torch" in sys.modules)
        
        # Helper to safely load torch and handle DLL path resolution
        def import_torch_safe():
            log.info("[Model Loader] Step 1: Importing torch...")
            try:
                import torch
                log.info("[Model Loader] torch imported successfully. Module file: %s", torch.__file__)
                return torch
            except Exception as e:
                log.warning("[Model Loader] Initial torch import failed: %s. Attempting DLL search path recovery...", e)
                # Attempt recovery by locating the torch directory and adding it via os.add_dll_directory
                try:
                    import importlib.util
                    spec = importlib.util.find_spec("torch")
                    if spec and spec.submodule_search_locations:
                        torch_dir = spec.submodule_search_locations[0]
                        torch_lib = os.path.join(torch_dir, "lib")
                        log.info("[Model Loader] Found torch lib path: %s", torch_lib)
                        if os.path.isdir(torch_lib):
                            if hasattr(os, "add_dll_directory"):
                                os.add_dll_directory(torch_lib)
                                log.info("[Model Loader] Added torch/lib to DLL directory search paths.")
                    import torch
                    log.info("[Model Loader] torch imported successfully after recovery! Version: %s", torch.__version__)
                    return torch
                except Exception as recovery_exc:
                    log.error("[Model Loader] Torch recovery import failed: %s", recovery_exc)
                    raise

        # Loading YOLO Model
        try:
            # Safe torch import first
            import_torch_safe()
            
            log.info("[Model Loader] Step 2: Importing ultralytics...")
            from ultralytics import YOLO
            
            log.info("[Model Loader] Step 3: Loading YOLO model from %s...", MODEL_PATH)
            self.yolo = YOLO(MODEL_PATH)
            self._yolo_ok = True
            log.info("YOLO model loaded: %s", MODEL_PATH)
        except Exception as exc:
            log.error("YOLO load failed! Detailed Traceback:\n%s", traceback.format_exc())
            self.status_bar.showMessage("❌ YOLO model load failed (see log for details)")

        # Loading PaddleOCR Model
        try:
            log.info("[Model Loader] Step 4: Importing paddleocr...")
            from paddleocr import PaddleOCR
            
            log.info("[Model Loader] Step 5: Initializing PaddleOCR...")
            self.ocr = PaddleOCR(
                use_textline_orientation=True, lang="en",
                text_det_limit_side_len=320 if OCR_FAST_MODE else 384)
            self._ocr_ok = True
            log.info("PaddleOCR engine loaded.")
        except Exception as exc:
            log.error("PaddleOCR load failed! Detailed Traceback:\n%s", traceback.format_exc())
            self.status_bar.showMessage("❌ PaddleOCR engine load failed (see log for details)")

        # Update the UI counter badge if referenced
        if hasattr(self, "_model_count_lbl") and self._model_count_lbl:
            ok_count = (1 if self._yolo_ok else 0) + (1 if self._ocr_ok else 0)
            self._model_count_lbl.setText(f"{ok_count}/2")
            
        if self._yolo_ok and self._ocr_ok:
            self.status_bar.showMessage("✅ AI models loaded successfully.", 5000)
        else:
            warnings = []
            if not self._yolo_ok: warnings.append("YOLO")
            if not self._ocr_ok: warnings.append("PaddleOCR")
            self.status_bar.showMessage(f"⚠️ Warning: Failed to load {', '.join(warnings)} (see logs).")

    # ── UI build ───────────────────────────────────────────────────────────────

    def _build_ui(self):
        root = QWidget(); root.setObjectName("root")
        self.setCentralWidget(root)
        main = QVBoxLayout(root)
        main.setContentsMargins(0, 0, 0, 0); main.setSpacing(0)

        # ── Header ────────────────────────────────────────────────────────────
        hdr = QWidget(); hdr.setObjectName("headerBar"); hdr.setFixedHeight(68)
        hl  = QHBoxLayout(hdr); hl.setContentsMargins(22, 0, 22, 0)

        logo_row = QHBoxLayout(); logo_row.setSpacing(10)
        dot = PulsingDot(C_ACCENT); logo_row.addWidget(dot)
        title_col = QVBoxLayout(); title_col.setSpacing(1)
        t = QLabel("MedScan Pro"); t.setObjectName("appTitle")
        t.setFont(QFont("Trebuchet MS", 19, QFont.Bold))
        s = QLabel("HYBRID OCR  ·  YOLO DETECTION  ·  INVENTORY MATCHING  ·  300 mm SCAN TRAY")
        s.setObjectName("appSubtitle")
        title_col.addWidget(t); title_col.addWidget(s)
        logo_row.addLayout(title_col)
        hl.addLayout(logo_row); hl.addStretch()

        self._mode_chip = ModeChip()
        hl.addWidget(self._mode_chip); hl.addSpacing(20)

        ocr_hint = QLabel(f"OCR: {'HYBRID' if OCR_FAST_MODE else 'FULL'}")
        ocr_hint.setStyleSheet(
            f"color:{C_ACCENT2}; font-size:10px; font-weight:700; letter-spacing:1px;"
            f" background:{C_ACCENT2}15; border:1px solid {C_ACCENT2}40;"
            f" border-radius:10px; padding:4px 10px;")
        hl.addWidget(ocr_hint); hl.addSpacing(20)

        self._model_count_lbl = None
        for label, attr in [
            ("DB ITEMS", f"{len(self.db) if self._db_ok else 0}"),
            ("MODELS",   f"{'2' if self._yolo_ok and self._ocr_ok else '0'}/2"),
        ]:
            col = QVBoxLayout(); col.setSpacing(1); col.setAlignment(Qt.AlignCenter)
            vl  = QLabel(attr); vl.setObjectName("counterLabel")
            vl.setFont(QFont("Trebuchet MS", 22, QFont.Bold)); vl.setAlignment(Qt.AlignCenter)
            if label == "MODELS":
                self._model_count_lbl = vl
            ll  = QLabel(label); ll.setObjectName("counterSub"); ll.setAlignment(Qt.AlignCenter)
            col.addWidget(vl); col.addWidget(ll)
            hl.addLayout(col); hl.addSpacing(24)

        self._scan_count_lbl = QLabel("0")
        self._scan_count_lbl.setObjectName("counterLabel")
        self._scan_count_lbl.setFont(QFont("Trebuchet MS", 22, QFont.Bold))
        self._scan_count_lbl.setAlignment(Qt.AlignCenter)
        sc_col = QVBoxLayout(); sc_col.setSpacing(1); sc_col.setAlignment(Qt.AlignCenter)
        sc_col.addWidget(self._scan_count_lbl)
        sc_lbl = QLabel("SCANS"); sc_lbl.setObjectName("counterSub"); sc_lbl.setAlignment(Qt.AlignCenter)
        sc_col.addWidget(sc_lbl)
        hl.addLayout(sc_col)
        main.addWidget(hdr)

        # ── Body ──────────────────────────────────────────────────────────────
        body = QHBoxLayout()
        body.setContentsMargins(14, 14, 14, 14); body.setSpacing(14)

        # Left panel — camera
        left = QWidget(); left.setObjectName("leftPanel")
        ll   = QVBoxLayout(left); ll.setContentsMargins(14, 14, 14, 14); ll.setSpacing(10)

        cam_hdr = QHBoxLayout()
        sec_cam = QLabel("● CAMERA FEED  ·  SCAN AREA 300 × 300 mm")
        sec_cam.setObjectName("sectionTitle")
        sec_cam.setFont(QFont("Trebuchet MS", 10, QFont.Bold))
        cam_hdr.addWidget(sec_cam); cam_hdr.addStretch()
        kb_hint = QLabel("SPACE  freeze+YOLO   ENTER  OCR   R  live")
        kb_hint.setStyleSheet("color:#1E3555; font-size:9px; letter-spacing:0.5px;")
        cam_hdr.addWidget(kb_hint)
        ll.addLayout(cam_hdr)

        self.cam_label = QLabel()
        self.cam_label.setObjectName("cameraFeed")
        self.cam_label.setAlignment(Qt.AlignCenter)
        self.cam_label.setMinimumSize(640, 380)
        self.cam_label.setText("Initialising camera…")
        ll.addWidget(self.cam_label, 1)

        # Detection badges
        badges_row = QHBoxLayout(); badges_row.setSpacing(8)
        self._med_badge = self._mk_badge("MEDICINE",  C_ACCENT2, 0)
        self._st_badge  = self._mk_badge("STRIP TOP", C_WARN,    0)
        for b in [self._med_badge, self._st_badge]:
            badges_row.addWidget(b)
        badges_row.addStretch()
        # Resolution info label
        self._res_lbl = QLabel("camera: initialising…")
        self._res_lbl.setStyleSheet(f"color:#1E3555; font-size:9px;")
        badges_row.addWidget(self._res_lbl)
        ll.addLayout(badges_row)

        # Main buttons row
        btn_row = QHBoxLayout(); btn_row.setSpacing(8)

        self.capture_btn = QPushButton("  SPACE · Capture + YOLO")
        self.capture_btn.setObjectName("captureBtn")
        self.capture_btn.setFont(QFont("Trebuchet MS", 13, QFont.Bold))
        self.capture_btn.setFixedHeight(46)
        self.capture_btn.clicked.connect(self._on_capture)
        btn_row.addWidget(self.capture_btn, 3)

        self.ocr_btn = QPushButton("  ENTER · Run OCR")
        self.ocr_btn.setObjectName("ocrBtn")
        self.ocr_btn.setFont(QFont("Trebuchet MS", 13, QFont.Bold))
        self.ocr_btn.setFixedHeight(46)
        self.ocr_btn.clicked.connect(self._on_enter_pressed)
        self.ocr_btn.setEnabled(False)
        btn_row.addWidget(self.ocr_btn, 2)

        self.confirm_btn = QPushButton("✅ Confirm Dispense")
        self.confirm_btn.setObjectName("ocrBtn")
        self.confirm_btn.setFont(QFont("Trebuchet MS", 12, QFont.Bold))
        self.confirm_btn.setFixedHeight(46)
        self.confirm_btn.clicked.connect(self._on_confirm_dispense)
        self.confirm_btn.setEnabled(False)
        btn_row.addWidget(self.confirm_btn, 2)

        self.reset_btn = QPushButton("R · Live")
        self.reset_btn.setObjectName("ghostBtn"); self.reset_btn.setFixedHeight(46)
        self.reset_btn.clicked.connect(self._on_recapture)
        btn_row.addWidget(self.reset_btn)

        self.save_btn = QPushButton("💾  Save")
        self.save_btn.setObjectName("ghostBtn"); self.save_btn.setFixedHeight(46)
        self.save_btn.clicked.connect(self._on_save)
        self.save_btn.setEnabled(False)
        btn_row.addWidget(self.save_btn)

        self.export_btn = QPushButton("📤  Export")
        self.export_btn.setObjectName("ghostBtn"); self.export_btn.setFixedHeight(46)
        self.export_btn.clicked.connect(self._on_export)
        btn_row.addWidget(self.export_btn)

        # Calibrate toggle button
        self.calib_btn = QPushButton("⊞  Calibrate")
        self.calib_btn.setObjectName("calibBtn")
        self.calib_btn.setFixedHeight(46)
        self.calib_btn.setCheckable(True)
        self.calib_btn.clicked.connect(self._toggle_calibrate)
        btn_row.addWidget(self.calib_btn)

        ll.addLayout(btn_row)

        # Progress bar
        self.progress = QProgressBar()
        self.progress.setRange(0, 100); self.progress.setValue(0)
        self.progress.setFixedHeight(5); self.progress.setTextVisible(False)
        self.progress.setStyleSheet("""
            QProgressBar { background:#080F20; border:none; border-radius:3px; }
            QProgressBar::chunk {
                background:qlineargradient(x1:0,y1:0,x2:1,y2:0,stop:0 #00C6E0,stop:1 #00FF9D);
                border-radius:3px;
            }
        """)
        self.progress.hide()
        ll.addWidget(self.progress)

        # ── Calibration panel (hidden by default) ─────────────────────────────
        self._calib_panel = QFrame()
        self._calib_panel.setObjectName("calibPanel")
        self._calib_panel.setVisible(False)
        cp   = QVBoxLayout(self._calib_panel)
        cp.setContentsMargins(12, 10, 12, 10); cp.setSpacing(8)

        calib_title = QLabel("⊞  SCAN AREA CALIBRATION  —  align the ROI rectangle to the 300 × 300 mm tray")
        calib_title.setStyleSheet(f"color:{C_WARN}; font-size:10px; font-weight:700; letter-spacing:0.8px;")
        cp.addWidget(calib_title)

        hint = QLabel(
            "The green rectangle on the camera feed shows the current scan area.\n"
            "Adjust x1/y1/x2/y2 until it tightly covers your physical tray, then click Apply & Resume.")
        hint.setStyleSheet(f"color:{C_MUTED}; font-size:9px; line-height:1.6;")
        cp.addWidget(hint)

        spin_row = QHBoxLayout(); spin_row.setSpacing(6)
        for lbl_text, attr_name in [("x1:", "_roi_x1"), ("y1:", "_roi_y1"),
                                     ("x2:", "_roi_x2"), ("y2:", "_roi_y2")]:
            lbl = QLabel(lbl_text)
            lbl.setStyleSheet(f"color:{C_MUTED}; font-size:10px;")
            spin_row.addWidget(lbl)
            sp = QSpinBox(); sp.setRange(0, 9999); sp.setFixedWidth(82)
            setattr(self, attr_name, sp)
            spin_row.addWidget(sp)
        cp.addLayout(spin_row)

        for attr in ["_roi_x1", "_roi_y1", "_roi_x2", "_roi_y2"]:
            getattr(self, attr).valueChanged.connect(self._on_roi_spinbox_changed)

        calib_btns = QHBoxLayout(); calib_btns.setSpacing(8)
        for label, fn, obj in [
            ("⊞ Auto-center",   self._roi_auto_center,       "ghostBtn"),
            ("□ Make Square",   self._roi_make_square,        "ghostBtn"),
            ("📋 Copy SCAN_ROI",self._roi_copy_to_clipboard,  "ghostBtn"),
            ("✅ Apply & Resume",self._roi_apply,              "ocrBtn"),
        ]:
            b = QPushButton(label); b.setObjectName(obj)
            b.setFixedHeight(36); b.clicked.connect(fn)
            calib_btns.addWidget(b)
        cp.addLayout(calib_btns)

        ll.addWidget(self._calib_panel)
        body.addWidget(left, 3)

        # ── Right side ────────────────────────────────────────────────────────
        right_col = QVBoxLayout(); right_col.setSpacing(12)
        self.tabs = QTabWidget()
        self.tabs.setFont(QFont("Trebuchet MS", 11))

        # Results tab
        cards_w = QWidget()
        cards_l = QVBoxLayout(cards_w)
        cards_l.setContentsMargins(10, 10, 10, 10); cards_l.setSpacing(8)
        res_hdr = QHBoxLayout()
        sec_res = QLabel("● DETECTION RESULTS")
        sec_res.setObjectName("sectionTitle")
        sec_res.setFont(QFont("Trebuchet MS", 10, QFont.Bold))
        res_hdr.addWidget(sec_res); res_hdr.addStretch()
        clr = QPushButton("Clear"); clr.setObjectName("clearBtn")
        clr.clicked.connect(self._clear_cards)
        res_hdr.addWidget(clr)
        cards_l.addLayout(res_hdr)
        self.cards_area = QScrollArea(); self.cards_area.setWidgetResizable(True)
        self.cards_container = QWidget()
        self.cards_layout = QVBoxLayout(self.cards_container)
        self.cards_layout.setAlignment(Qt.AlignTop); self.cards_layout.setSpacing(8)
        self._empty_lbl = QLabel(
            "No scans yet.\nSpace/Enter → freeze + YOLO   ·   Enter after boxes → OCR   ·   R → live camera")
        self._empty_lbl.setAlignment(Qt.AlignCenter)
        self._empty_lbl.setStyleSheet(f"color:#1A2E45; font-size:12px; line-height:1.9;")
        self.cards_layout.addWidget(self._empty_lbl)
        self.cards_area.setWidget(self.cards_container)
        cards_l.addWidget(self.cards_area, 1)
        self.tabs.addTab(cards_w, "  Results  ")

        # Log tab
        log_w = QWidget(); log_l = QVBoxLayout(log_w); log_l.setContentsMargins(8, 8, 8, 8)
        self.log_view = QTextEdit(); self.log_view.setObjectName("logView")
        self.log_view.setReadOnly(True)
        self.log_view.setFont(QFont("Cascadia Code", 10))
        self.log_view.setPlaceholderText(
            "Hybrid OCR log:\n"
            "⚡ = fast OCR sufficient\n"
            "🔄 = escalated to full OCR\n"
            "✅ = DB match found\n"
            "🧹 = duplicates removed by IoU dedup\n"
        )
        log_l.addWidget(self.log_view)
        self.tabs.addTab(log_w, "  OCR Log  ")
        right_col.addWidget(self.tabs, 3)

        # History panel
        hist   = QWidget(); hist.setObjectName("historyPanel")
        hist_l = QVBoxLayout(hist); hist_l.setContentsMargins(12, 10, 12, 10); hist_l.setSpacing(8)
        hist_hdr = QHBoxLayout()
        sec_h = QLabel("● SCAN HISTORY")
        sec_h.setObjectName("sectionTitle"); sec_h.setFont(QFont("Trebuchet MS", 10, QFont.Bold))
        hist_hdr.addWidget(sec_h); hist_hdr.addStretch()
        hist_l.addLayout(hist_hdr)
        self.hist_scroll = QScrollArea(); self.hist_scroll.setWidgetResizable(True)
        self.hist_container = QWidget()
        self.hist_layout = QVBoxLayout(self.hist_container)
        self.hist_layout.setAlignment(Qt.AlignTop); self.hist_layout.setSpacing(5)
        self._hist_empty = QLabel("No history yet")
        self._hist_empty.setStyleSheet(f"color:#1A2E45; font-size:11px;")
        self.hist_layout.addWidget(self._hist_empty)
        self.hist_scroll.setWidget(self.hist_container)
        hist_l.addWidget(self.hist_scroll, 1)
        right_col.addWidget(hist, 1)

        right_w = QWidget(); right_w.setLayout(right_col)
        body.addWidget(right_w, 2)
        main.addLayout(body, 1)

        self.status_bar = QStatusBar()
        self.status_bar.setFont(QFont("Trebuchet MS", 10))
        self.setStatusBar(self.status_bar)

    def _mk_badge(self, label: str, color: str, count: int) -> QLabel:
        w = QLabel(f"  {label}  {count}  ")
        w.setStyleSheet(f"""
            background:{color}18; color:{color};
            border:1px solid {color}40; border-radius:9px;
            font-size:9px; font-weight:700; padding:3px 6px; letter-spacing:0.5px;
        """)
        return w

    # ── Mode state machine ─────────────────────────────────────────────────────

    def _set_mode(self, mode: str):
        self._mode = mode
        self._mode_chip.set_mode(mode)
        is_busy      = mode in ("detecting", "ocr")
        is_detected  = mode == "detected"
        is_calibrating = self._calibrate_mode

        self.capture_btn.setEnabled(not is_busy and not is_calibrating)
        self.ocr_btn.setEnabled(is_detected and not is_calibrating)
        has_match = any(r.get("match") for r in self._last_results)
        self.confirm_btn.setEnabled(mode == "done" and has_match and self._inventory_ok and not is_calibrating)
        self.reset_btn.setEnabled(not is_busy)

        labels = {
            "live":      "  SPACE · Capture + YOLO",
            "detecting": "⏳  Running YOLO…",
            "detected":  "  SPACE · New Capture",
            "ocr":       "⏳  OCR Running…",
            "done":      "  SPACE · New Capture",
        }
        self.capture_btn.setText(labels.get(mode, "  SPACE · Capture + YOLO"))

    # ── Camera ─────────────────────────────────────────────────────────────────

    def _start_camera(self):
        self.cam_thread = CameraThread()
        self.cam_thread.frame_ready.connect(self._on_frame)
        self.cam_thread.status.connect(self._on_camera_status)
        self.cam_thread.start()

    def _on_camera_status(self, msg: str):
        self.status_bar.showMessage(msg)
        if "Camera locked at" in msg or "Camera is at" in msg:
            # Extract and show resolution in badge row
            parts = msg.split()
            for i, p in enumerate(parts):
                if "×" in p and p[0].isdigit():
                    self._res_lbl.setText(f"camera: {p}")
                    break

    def _on_frame(self, raw_frame: np.ndarray):
        self._current_raw_frame  = raw_frame
        scan                     = apply_scan_roi(raw_frame)
        self._current_scan_frame = scan

        if self._calibrate_mode:
            # Show full raw frame with ROI overlay using spinbox values
            self._display_calibrate_view(raw_frame)
        elif self._mode == "live":
            disp = draw_viewfinder(scan) if SHOW_ROI_OVERLAY else scan
            self._show_in_label(disp)

    def _show_in_label(self, frame: np.ndarray):
        rgb  = np.ascontiguousarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
        h, w, ch = rgb.shape
        qimg = QImage(rgb.data, w, h, ch * w, QImage.Format_RGB888).copy()
        pix  = QPixmap.fromImage(qimg)
        self.cam_label.setPixmap(
            pix.scaled(self.cam_label.size(), Qt.KeepAspectRatio, Qt.SmoothTransformation))

    def _display_annotated(self, scan_frame: np.ndarray, results: List):
        ann = scan_frame.copy()
        med_n = st_n = 0
        for r in results:
            nm   = r["class_name"]
            conf = r["conf"]
            pts  = r.get("obb_pts")
            x1, y1, x2, y2 = r["box"]
            color = (60, 230, 110) if nm == "Medicine" else (80, 179, 255)
            if nm == "Medicine": med_n += 1
            else:                st_n  += 1

            if pts is not None and len(pts) == 4:
                draw_obb(ann, pts, color, thickness=2)
            else:
                cv2.rectangle(ann, (x1, y1), (x2, y2), color, 2)
                pts = _axis_aligned_pts(x1, y1, x2, y2)

            m     = r.get("match")
            raw_l = f"{m['full_brand_name']}  {m['strength']}" if m else f"{nm}  {conf:.0%}"
            label_obb(ann, pts, raw_l[:52] + ("…" if len(raw_l) > 52 else ""), color)

        if SHOW_ROI_OVERLAY:
            ann = draw_viewfinder(ann)
        self._update_badges(med_n, st_n)
        self._show_in_label(ann)

    def _update_badges(self, med_n: int, st_n: int):
        def upd(badge, lbl, color, count):
            a = "44" if count > 0 else "12"
            badge.setText(f"  {lbl}  {count}  ")
            badge.setStyleSheet(f"""
                background:{color}{a}; color:{color if count > 0 else color + '66'};
                border:1px solid {color}{'60' if count > 0 else '20'};
                border-radius:9px; font-size:9px; font-weight:700; padding:3px 6px;
            """)
        upd(self._med_badge, "MEDICINE",  C_ACCENT2, med_n)
        upd(self._st_badge,  "STRIP TOP", C_WARN,    st_n)

    # ── Calibration ────────────────────────────────────────────────────────────

    def _toggle_calibrate(self, checked: bool):
        self._calibrate_mode = checked
        self.calib_btn.setText("⊞  Exit Calibrate" if checked else "⊞  Calibrate")
        self._calib_panel.setVisible(checked)
        self._set_mode(self._mode)   # refresh button enabled states

        if checked:
            self._mode_chip.set_mode("calibrate")
            raw = self._current_raw_frame
            if raw is not None:
                h, w = raw.shape[:2]
                x1, y1, x2, y2 = get_scan_roi(w, h)
                for sp, mx in [(self._roi_x1, w), (self._roi_x2, w),
                                (self._roi_y1, h), (self._roi_y2, h)]:
                    sp.setMaximum(mx)
                for sp, val in [(self._roi_x1, x1), (self._roi_y1, y1),
                                 (self._roi_x2, x2), (self._roi_y2, y2)]:
                    sp.blockSignals(True); sp.setValue(val); sp.blockSignals(False)
                self._display_calibrate_view(raw)
            self.status_bar.showMessage(
                "📐  Calibrate mode — adjust spinboxes to cover the 300×300 mm tray, then Apply & Resume")
        else:
            self._mode_chip.set_mode(self._mode)
            self.status_bar.showMessage("🟢  Ready")

    def _display_calibrate_view(self, raw_frame: np.ndarray):
        x1 = self._roi_x1.value(); y1 = self._roi_y1.value()
        x2 = self._roi_x2.value(); y2 = self._roi_y2.value()
        vis = draw_roi_overlay(raw_frame, x1, y1, x2, y2)
        self._show_in_label(vis)

    def _on_roi_spinbox_changed(self):
        if not self._calibrate_mode:
            return
        raw = self._current_raw_frame
        if raw is not None:
            self._display_calibrate_view(raw)
        x1 = self._roi_x1.value(); y1 = self._roi_y1.value()
        x2 = self._roi_x2.value(); y2 = self._roi_y2.value()
        w_ = x2 - x1; h_ = y2 - y1
        sq = "SQUARE ✓" if abs(w_ - h_) < 5 else f"⚠ not square ({w_}×{h_} px)"
        self.status_bar.showMessage(
            f"ROI: ({x1}, {y1}) → ({x2}, {y2})   {w_}×{h_} px   {sq}")

    def _roi_auto_center(self):
        raw = self._current_raw_frame
        if raw is None: return
        h, w = raw.shape[:2]
        side = min(w, h); cx = (w - side) // 2; cy = (h - side) // 2
        for sp, val in [(self._roi_x1, cx), (self._roi_y1, cy),
                         (self._roi_x2, cx + side), (self._roi_y2, cy + side)]:
            sp.setValue(val)

    def _roi_make_square(self):
        x1 = self._roi_x1.value(); y1 = self._roi_y1.value()
        x2 = self._roi_x2.value(); y2 = self._roi_y2.value()
        cx = (x1 + x2) // 2; cy = (y1 + y2) // 2
        half = min(x2 - x1, y2 - y1) // 2
        for sp, val in [(self._roi_x1, cx - half), (self._roi_y1, cy - half),
                         (self._roi_x2, cx + half), (self._roi_y2, cy + half)]:
            sp.setValue(val)

    def _roi_copy_to_clipboard(self):
        x1 = self._roi_x1.value(); y1 = self._roi_y1.value()
        x2 = self._roi_x2.value(); y2 = self._roi_y2.value()
        text = f"SCAN_ROI = ({x1}, {y1}, {x2}, {y2})"
        QApplication.clipboard().setText(text)
        self.status_bar.showMessage(f"📋 Copied to clipboard: {text}")

    def _roi_apply(self):
        global SCAN_ROI
        x1 = self._roi_x1.value(); y1 = self._roi_y1.value()
        x2 = self._roi_x2.value(); y2 = self._roi_y2.value()
        if x2 <= x1 or y2 <= y1:
            self.status_bar.showMessage("❌  Invalid ROI: x2 must be > x1, y2 must be > y1")
            return
        SCAN_ROI = (x1, y1, x2, y2)
        _save_roi_config(x1, y1, x2, y2)
        self.calib_btn.setChecked(False)
        self._toggle_calibrate(False)
        w_ = x2 - x1; h_ = y2 - y1
        sq = "square ✓" if abs(w_ - h_) < 5 else f"⚠ not square ({w_}×{h_})"
        self.status_bar.showMessage(
            f"✅  ROI applied: ({x1}, {y1}) → ({x2}, {y2})  {sq}  — saved to scan_roi_config.json")

    # ── Keyboard shortcuts ─────────────────────────────────────────────────────

    def _setup_shortcuts(self):
        for key, fn in [
            (Qt.Key_Space,  self._on_capture),
            (Qt.Key_Return, self._on_enter_pressed),
            (Qt.Key_Enter,  self._on_enter_pressed),
            (Qt.Key_R,      self._on_recapture),
        ]:
            sc = QShortcut(QKeySequence(key), self)
            sc.setContext(Qt.ApplicationShortcut)
            sc.activated.connect(fn)

    def _on_enter_pressed(self):
        if self._calibrate_mode:
            return
        if self._mode == "live":          self._on_capture()
        elif self._mode == "detected":    self._on_run_ocr()
        elif self._mode == "done":
            self.status_bar.showMessage("ℹ️  Scan done. Press R to reset or Space for new capture.")
        else:
            self._on_run_ocr()

    def keyPressEvent(self, event):
        if event.key() == Qt.Key_Space:                   self._on_capture();       return
        if event.key() in (Qt.Key_Return, Qt.Key_Enter):  self._on_enter_pressed(); return
        if event.key() == Qt.Key_R:                       self._on_recapture();     return
        super().keyPressEvent(event)

    # ── YOLO capture ───────────────────────────────────────────────────────────

    def _on_capture(self):
        if self._scan_running or self._calibrate_mode:
            return
        if self._current_scan_frame is None:
            self.status_bar.showMessage("❌  No frame yet — is the camera connected?"); return
        if not self._yolo_ok:
            self.status_bar.showMessage("❌  YOLO model not loaded (place best.pt next to script)"); return

        self._scan_running   = True
        self._captured_frame = self._current_scan_frame.copy()  # always SCAN_SIZE × SCAN_SIZE
        self._captured_dets  = []
        self._last_results   = []
        self.confirm_btn.setEnabled(False)
        self._set_mode("detecting")
        self.save_btn.setEnabled(False)
        self.progress.hide()
        self.log_view.clear()
        self.tabs.setCurrentIndex(1)
        self._show_in_label(self._captured_frame)

        self._yolo_thread = YOLODetectThread(self._captured_frame, self.yolo)
        self._yolo_thread.log_msg.connect(
            lambda m: self.log_view.append(f"<span style='color:#308060'>{m}</span>"))
        self._yolo_thread.detections_ready.connect(self._on_yolo_done)
        self._yolo_thread.start()
        self.status_bar.showMessage("📸  Frame frozen — running high-accuracy YOLO on scan area…")

    def _on_yolo_done(self, detections: List):
        self._scan_running  = False
        self._captured_dets = detections

        results = []
        for i, (box, cls, conf) in enumerate(detections):
            x1, y1, x2, y2 = map(int, box)
            obb_pts, obb_angle = fit_oriented_box(self._captured_frame, x1, y1, x2, y2)
            results.append({
                "det_idx":    i,
                "class_name": CLASS_NAMES.get(int(cls), "?"),
                "conf":       float(conf),
                "box":        [x1, y1, x2, y2],
                "obb_pts":    obb_pts,
                "obb_angle":  obb_angle,
                "ocr_hits":   [],
                "match":      None,
            })
        self._last_results = results

        self._clear_cards(keep_empty=False)
        if results:
            for r in results:
                self.cards_layout.addWidget(MedicineCard(r))
            self._display_annotated(self._captured_frame, results)
            self.save_btn.setEnabled(True)
            self._set_mode("detected")
            self.status_bar.showMessage(
                f"✅  YOLO: {len(results)} object(s) — press Enter to run OCR, or R to recapture")
            self.log_view.append(
                f"<span style='color:{C_ACCENT}'>→ Press Enter to run "
                f"{'hybrid' if OCR_FAST_MODE else 'full'} OCR on these boxes.</span>")
        else:
            self._empty_lbl.setText("No objects detected by YOLO.\nPress R to return to live camera.")
            self.cards_layout.addWidget(self._empty_lbl)
            self._update_badges(0, 0)
            self._show_in_label(self._captured_frame)
            self._set_mode("live")
            self.status_bar.showMessage("⚠️  No YOLO detections. Press R for live camera.")

        self.tabs.setCurrentIndex(0)

    # ── OCR ────────────────────────────────────────────────────────────────────

    def _on_run_ocr(self):
        if self._scan_running:
            return
        if self._captured_frame is None or not self._captured_dets:
            self.status_bar.showMessage("📸  No YOLO boxes yet — capturing first")
            self._on_capture(); return
        if not self._ocr_ok:
            self.status_bar.showMessage("❌  OCR engine not loaded"); return
        if not self._db_ok:
            self.status_bar.showMessage("❌  CSV database not loaded"); return

        self._scan_running = True
        self._set_mode("ocr")
        self.save_btn.setEnabled(False)
        self.progress.show(); self.progress.setValue(0)
        self.tabs.setCurrentIndex(1)
        self.log_view.append(
            f"<span style='color:{C_ACCENT}'>Starting {'hybrid' if OCR_FAST_MODE else 'full'} OCR + inventory matching…</span>")

        self._ocr_thread = OCROnlyThread(
            self._captured_frame.copy(), self._captured_dets,
            self.ocr, self.db, prev_results=self._last_results)
        self._ocr_thread.result_ready.connect(self._on_ocr_done)
        self._ocr_thread.progress.connect(
            lambda cur, tot: self.progress.setValue(int(cur / max(1, tot) * 100)))
        self._ocr_thread.log_msg.connect(
            lambda m: self.log_view.append(f"<span style='color:#3A8060'>{m}</span>"))
        self._ocr_thread.start()
        self.status_bar.showMessage(
            f"🔍  Running {'hybrid' if OCR_FAST_MODE else 'full'} OCR on YOLO boxes…")

    def _on_ocr_done(self, results: List):
        self._last_results = results
        self._scan_running = False
        self._set_mode("done")
        self.progress.hide()
        self.save_btn.setEnabled(bool(results))

        ts      = datetime.now().strftime("%H:%M:%S")
        matches = [r for r in results if r.get("match")]

        # Cap history to prevent unbounded memory growth
        self._history.append({"ts": ts, "results": results})
        if len(self._history) > MAX_HISTORY_ENTRIES:
            self._history = self._history[-MAX_HISTORY_ENTRIES:]
        self._add_history_row(ts, results)

        self._clear_cards(keep_empty=False)
        if results:
            for r in results:
                self.cards_layout.addWidget(MedicineCard(r))
            self._display_annotated(self._captured_frame, results)
        else:
            self._empty_lbl.setText("No OCR results. Press R to recapture.")
            self.cards_layout.addWidget(self._empty_lbl)

        self.tabs.setCurrentIndex(0)
        self._scan_count += 1
        self._scan_count_lbl.setText(str(self._scan_count))

        msg = (f"✅  {len(matches)}/{len(results)} medicines identified. R = new capture  ·  {ts}"
               if matches else
               f"❌  No medicines matched. R = new capture  ·  {ts}")
        self.status_bar.showMessage(msg)
        self.log_view.append(
            f"<br><span style='color:{C_ACCENT}'>═══ OCR complete: {len(matches)}/{len(results)} matched ═══</span>")

    # ── Confirm dispense ───────────────────────────────────────────────────────

    def _group_dispense_items(self) -> Optional[Dict[str, Dict]]:
        """Build a {item_code: {...}} dict from matched results. Returns None on error."""
        matches = [r for r in self._last_results if r.get("match")]
        if not matches:
            return None
        grouped: Dict[str, Dict] = {}
        for r in matches:
            m = r.get("match") or {}
            item_code = str(m.get("item_code", "")).strip()
            if not item_code or item_code == "N/A":
                continue
            if item_code not in grouped:
                grouped[item_code] = {
                    "item_code":         item_code,
                    "qty":               0,
                    "ocr_texts":         [],
                    "matched_name":      str(m.get("match_name") or m.get("full_brand_name") or ""),
                    "matched_strength":  str(m.get("strength") or ""),
                    "display_name":      str(m.get("full_brand_name") or m.get("match_name") or item_code),
                    "confidences":       [],
                }
            grouped[item_code]["qty"] += 1
            ocr_text = " | ".join(t.get("text", "") for t in r.get("ocr_hits", []))
            if ocr_text:
                grouped[item_code]["ocr_texts"].append(ocr_text)
            try:
                grouped[item_code]["confidences"].append(float(m.get("total_score") or 0.0))
            except Exception:
                pass
        return grouped or None

    def _execute_dispense(self, grouped: Dict[str, Dict]):
        """Call confirm_dispense for each item group, sync, and update UI."""
        results_list = []
        for g in grouped.values():
            confs = g.get("confidences") or [0.0]
            avg_conf = sum(confs) / max(1, len(confs))
            result = _confirm_dispense_fn(
                item_code=g["item_code"], qty=g["qty"],
                ocr_text=" || ".join(g.get("ocr_texts") or []),
                matched_name=g["matched_name"], matched_strength=g["matched_strength"],
                confidence=avg_conf)
            results_list.append((g, result))

        sync_result = sync_unsynced_transactions()
        sync_msg = (f"cloud synced ({sync_result.get('synced_count', 0)})"
                    if sync_result.get("ok")
                    else f"cloud pending: {sync_result.get('reason', 'unknown')}")

        self.confirm_btn.setEnabled(False)
        total_units  = sum(g["qty"] for g, _ in results_list)
        status_parts = [
            f"{g['item_code']} ×{g['qty']} → stock {res['quantity_after']}"
            for g, res in results_list
        ]
        status_text = "; ".join(status_parts)
        self.status_bar.showMessage(
            f"✅ Dispensed {total_units} unit(s). {status_text} · {sync_msg}")
        self.log_view.append(
            f"<br><span style='color:{C_ACCENT}'>✅ DISPENSED {total_units} unit(s): "
            f"{status_text} · {sync_msg}</span>")

    def _on_confirm_dispense(self):
        if not self._inventory_ok or not INVENTORY_SYNC_AVAILABLE:
            QMessageBox.warning(self, "Inventory sync not available",
                                "sync_engine.py is missing or the local DB could not be initialised.")
            return

        grouped = self._group_dispense_items()
        if not grouped:
            self.status_bar.showMessage("⚠️  No matched medicine with a valid item_code to dispense.")
            return

        summary_lines = [
            f"• {g['display_name']}\n"
            f"  Strength: {g['matched_strength'] or 'N/A'}\n"
            f"  Item code: {g['item_code']}\n"
            f"  Quantity to dispense: {g['qty']}"
            for g in grouped.values()
        ]
        reply = QMessageBox.question(
            self, "Confirm dispense",
            "Confirm dispense these detected medicines?\n\n"
            + "\n\n".join(summary_lines)
            + "\n\nNote: if YOLO/OCR duplicated a box by mistake, press No and rescan.",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No)

        if reply != QMessageBox.Yes:
            self.status_bar.showMessage("Dispense cancelled.")
            return

        try:
            self._execute_dispense(grouped)
        except Exception as exc:
            log.exception("Dispense failed")
            QMessageBox.critical(self, "Dispense failed", str(exc))
            self.status_bar.showMessage(f"❌ Dispense failed: {exc}")

    # ── Reset ──────────────────────────────────────────────────────────────────

    def _on_recapture(self):
        if self._scan_running:
            self.status_bar.showMessage("⚠️  Wait for current process to finish before pressing R"); return
        self._captured_frame = None
        self._captured_dets  = []
        self._last_results   = []
        self.confirm_btn.setEnabled(False)
        self.save_btn.setEnabled(False)
        self.progress.hide(); self.progress.setValue(0)
        self._clear_cards(keep_empty=True)
        self._update_badges(0, 0)
        self.tabs.setCurrentIndex(0)
        self._set_mode("live")
        if self._current_scan_frame is not None:
            disp = draw_viewfinder(self._current_scan_frame) if SHOW_ROI_OVERLAY else self._current_scan_frame
            self._show_in_label(disp)
        else:
            self.cam_label.setText("Live camera restarting…")
        self.status_bar.showMessage("🟢  Live camera — Space or Enter to capture + YOLO")

    # ── History & cards ────────────────────────────────────────────────────────

    def _add_history_row(self, ts: str, results: List):
        if self._hist_empty.parent():
            self._hist_empty.setParent(None)
        self.hist_layout.insertWidget(0, HistoryRow(ts, results))

    def _clear_cards(self, keep_empty: bool = True):
        while self.cards_layout.count():
            item   = self.cards_layout.takeAt(0)
            widget = item.widget()
            if widget is None: continue
            if widget is self._empty_lbl: widget.setParent(None)
            else: widget.deleteLater()
        if keep_empty:
            self._empty_lbl.setText(
                "No scans yet.\nSpace/Enter → freeze + YOLO   ·   Enter after boxes → OCR   ·   R → live camera")
            self.cards_layout.addWidget(self._empty_lbl)

    # ── Save / Export ──────────────────────────────────────────────────────────

    def _on_save(self):
        base = self._captured_frame if self._captured_frame is not None else self._current_scan_frame
        if base is None or not self._last_results: return
        ts  = datetime.now().strftime("%Y%m%d_%H%M%S")
        ann = base.copy()
        for r in self._last_results:
            x1, y1, x2, y2 = r["box"]
            m     = r.get("match")
            color = (80, 232, 128) if m else (80, 80, 255)
            pts   = r.get("obb_pts")
            if pts is not None and len(pts) == 4:
                draw_obb(ann, pts, color, thickness=2)
            else:
                cv2.rectangle(ann, (x1, y1), (x2, y2), color, 2)
                pts = _axis_aligned_pts(x1, y1, x2, y2)
            if m:
                label_obb(ann, pts, f"{m['full_brand_name']} {m['strength']}"[:55], color)
        path = os.path.join(SAVE_DIR, f"result_{ts}.jpg")
        cv2.imwrite(path, ann)
        self.status_bar.showMessage(f"✅  Saved: {path}")

    def _on_export(self):
        if not self._history:
            QMessageBox.information(self, "No data", "Run at least one scan first."); return
        path, _ = QFileDialog.getSaveFileName(self, "Export scan history", "", "JSON (*.json);;CSV (*.csv)")
        if not path: return
        rows = []
        for h in self._history:
            for r in h["results"]:
                m = r.get("match") or {}
                rows.append({
                    "time":            h["ts"],
                    "class":           r["class_name"],
                    "yolo_conf":       r["conf"],
                    "ocr_mode":        r.get("ocr_mode", ""),
                    "brand_name":      m.get("brand_name", ""),
                    "full_brand_name": m.get("full_brand_name", ""),
                    "mal_number":      m.get("mal_number", ""),
                    "generic":         m.get("generic_name", ""),
                    "strength":        m.get("strength", ""),
                    "form":            m.get("dosage_form", ""),
                    "category":        m.get("category", ""),
                    "item_code":       m.get("item_code", ""),
                    "name_score":      m.get("name_score", ""),
                    "strength_score":  m.get("strength_score", ""),
                    "total_score":     m.get("total_score", ""),
                    "ocr_text":        " | ".join(t["text"] for t in r.get("ocr_hits", [])),
                })
        df = pd.DataFrame(rows)
        if path.lower().endswith(".csv"):
            df.to_csv(path, index=False)
        else:
            df.to_json(path, orient="records", indent=2)
        self.status_bar.showMessage(f"✅  Exported {len(rows)} records → {path}")

    def closeEvent(self, e):
        if hasattr(self, "cam_thread"):
            self.cam_thread.stop()
        e.accept()

# ══════════════════════════════════════════════════════════════════════════════
#  ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    app = QApplication(sys.argv)
    app.setApplicationName("MedScan Pro")
    app.setStyle("Fusion")
    pal = app.palette()
    pal.setColor(QPalette.Window,     QColor(C_BG))
    pal.setColor(QPalette.WindowText, QColor(C_TEXT))
    pal.setColor(QPalette.Base,       QColor(C_PANEL))
    pal.setColor(QPalette.Text,       QColor(C_TEXT))
    app.setPalette(pal)
    app.setStyleSheet(STYLESHEET)
    win = MedScanPro()
    win.show()
    sys.exit(app.exec_())

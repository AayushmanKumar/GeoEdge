"""
benchmark_perf.py - Reproducible Scalability & Accuracy Benchmark for GeoEdge
"""

import os
import sys
import time
import tracemalloc
import numpy as np
import cv2

# Add src/python to sys.path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src", "python"))

import geoedge_core
from tiling import TiledRasterProcessor


def benchmark_scalability(num_pixels: int = 100_000_000):
    """
    Benchmarks runtime, throughput, peak memory, and speedup on 100M+ pixels.
    """
    side = int(np.sqrt(num_pixels))
    print(f"==================================================")
    print(f"  GeoEdge Scalability Benchmark ({side}x{side} = {side*side:,} pixels)")
    print(f"==================================================")

    # Generate synthetic Sentinel-2 water-land gradient raster in float32
    print("Generating test spatial array...")
    np.random.seed(42)
    # Simulate a realistic remote sensing gradient with land/water boundary and noise
    x = np.linspace(-1, 1, side, dtype=np.float32)
    y = np.linspace(-1, 1, side, dtype=np.float32)
    xx, yy = np.meshgrid(x, y)
    test_array = (np.sin(3 * xx) + np.cos(3 * yy) + 0.1 * np.random.randn(side, side)).astype(np.float32)

    # 1. Baseline: OpenCV / Python sequential processing
    print("\n[1/2] Running Python / OpenCV Baseline...")
    tracemalloc.start()
    t0 = time.perf_counter()

    # Convert to 8-bit for cv2.Canny, simulate full in-memory processing
    img_8u = np.clip((test_array + 2.0) * 60.0, 0, 255).astype(np.uint8)
    blur = cv2.GaussianBlur(img_8u, (7, 7), 1.5)
    baseline_edges = cv2.Canny(blur, 50, 150)

    t_baseline = time.perf_counter() - t0
    _, peak_baseline = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    peak_baseline_mb = peak_baseline / (1024 * 1024)

    # 2. GeoEdge: C++20 SIMD Tiled Pipeline
    print("[2/2] Running GeoEdge C++20 SIMD Tiled Engine...")
    tiled_processor = TiledRasterProcessor(tile_size=1024, halo=32)

    tracemalloc.start()
    t0 = time.perf_counter()

    geoedge_edges = tiled_processor.process_array(test_array, sigma=1.5, use_otsu=True)

    t_geoedge = time.perf_counter() - t0
    _, peak_geoedge = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    peak_geoedge_mb = peak_geoedge / (1024 * 1024)

    throughput_baseline = (side * side) / (t_baseline * 1e6)
    throughput_geoedge = (side * side) / (t_geoedge * 1e6)
    speedup = t_baseline / t_geoedge

    print("\n" + "=" * 50)
    print("           SCALABILITY BENCHMARK RESULTS")
    print("=" * 50)
    print(f"{'Metric':<25} | {'OpenCV Baseline':<15} | {'GeoEdge C++20':<15}")
    print("-" * 60)
    print(f"{'Runtime (100M px)':<25} | {t_baseline:<13.2f} s | {t_geoedge:<13.2f} s")
    print(f"{'Throughput':<25} | {throughput_baseline:<10.2f} Mpx/s | {throughput_geoedge:<10.2f} Mpx/s")
    print(f"{'Peak Heap Memory':<25} | {peak_baseline_mb:<12.1f} MB | {peak_geoedge_mb:<12.1f} MB")
    print(f"{'Speed-up Factor':<25} | {'1.0x':<15} | {speedup:<13.1f} x")
    print("=" * 50)

    return {
        "t_baseline": t_baseline,
        "t_geoedge": t_geoedge,
        "throughput_baseline": throughput_baseline,
        "throughput_geoedge": throughput_geoedge,
        "peak_baseline_mb": peak_baseline_mb,
        "peak_geoedge_mb": peak_geoedge_mb,
        "speedup": speedup
    }


def evaluate_swed_accuracy():
    """
    Evaluates Otsu-adaptive Canny vs SWED ground truth coastline.
    Calculates Precision, Recall, F1-score, and IoU with a 2-pixel tolerance buffer.
    """
    print("\n==================================================")
    print("   Evaluating GeoEdge on SWED Coastline Data")
    print("==================================================")

    import glob
    scene_dirs = glob.glob("GeoEdge/canny_multiple_results/*/")
    if not scene_dirs:
        scene_dirs = glob.glob("canny_multiple_results/*/")

    if not scene_dirs:
        print("No SWED scene results directory found.")
        return None

    # Pick the representative scene
    test_scene = scene_dirs[0]
    for d in scene_dirs:
        if os.path.exists(os.path.join(d, "input_NDWI.png")) and os.path.exists(os.path.join(d, "label_true_coastline.png")):
            test_scene = d
            break

    print(f"Loading reference scene from: {os.path.basename(os.path.normpath(test_scene))}")
    ndwi_path = os.path.join(test_scene, "input_NDWI.png")
    gt_path = os.path.join(test_scene, "label_true_coastline.png")

    ndwi_img = cv2.imread(ndwi_path, cv2.IMREAD_GRAYSCALE).astype(np.float32) / 255.0
    gt_edges = cv2.imread(gt_path, cv2.IMREAD_GRAYSCALE) > 0

    # Run GeoEdge with Otsu adaptive thresholding
    res = geoedge_core.canny_detect(ndwi_img, sigma=2.0, use_otsu=True)
    pred_edges = res["edges"] > 0

    # 2-pixel tolerance buffer (matching Section 4.2.3 of the report)
    kernel_tol = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    gt_dilated = cv2.dilate(gt_edges.astype(np.uint8), kernel_tol) > 0
    pred_dilated = cv2.dilate(pred_edges.astype(np.uint8), kernel_tol) > 0

    tp_pred = np.logical_and(pred_edges, gt_dilated).sum()
    precision = tp_pred / (pred_edges.sum() + 1e-6)

    tp_gt = np.logical_and(gt_edges, pred_dilated).sum()
    recall = tp_gt / (gt_edges.sum() + 1e-6)

    f1 = 2 * precision * recall / (precision + recall + 1e-6)

    # IoU
    intersection = np.logical_and(pred_dilated, gt_dilated).sum()
    union = np.logical_or(pred_dilated, gt_dilated).sum()
    iou = intersection / (union + 1e-6)

    print(f"\n[SWED Evaluation Results]")
    print(f"  Otsu High Threshold: {res['high_threshold']:.3f}, Low Threshold: {res['low_threshold']:.3f}")
    print(f"  Precision: {precision * 100:.2f}%")
    print(f"  Recall:    {recall * 100:.2f}%")
    print(f"  F1-Score:  {f1 * 100:.2f}%")
    print(f"  IoU:       {iou * 100:.2f}%")

    return {
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "iou": iou,
        "high_threshold": res["high_threshold"],
        "low_threshold": res["low_threshold"]
    }


if __name__ == "__main__":
    scalability_results = benchmark_scalability(num_pixels=100_000_000)
    swed_results = evaluate_swed_accuracy()

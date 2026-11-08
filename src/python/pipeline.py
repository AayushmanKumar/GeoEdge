"""
pipeline.py - End-to-End GeoEdge Execution Pipeline
"""

import os
import sys
import argparse
import numpy as np

# Ensure src/python is in import path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import geoedge_core
from tiling import TiledRasterProcessor
from spectral import compute_ndwi, compute_mndwi


def run_pipeline(
    image_array: np.ndarray,
    sigma: float = 1.5,
    use_otsu: bool = True,
    tile_size: int = 1024,
    halo: int = 32
) -> np.ndarray:
    """
    Runs the complete GeoEdge pipeline on a 2D float32 raster.
    """
    processor = TiledRasterProcessor(tile_size=tile_size, halo=halo)
    edges = processor.process_array(image_array, sigma=sigma, use_otsu=use_otsu)
    return edges


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="GeoEdge: Adaptive High-Throughput Edge Detection")
    parser.add_argument("--sigma", type=float, default=1.5, help="Gaussian smoothing sigma")
    parser.add_argument("--tile-size", type=int, default=1024, help="Tile chunk size in pixels")
    parser.add_argument("--halo", type=int, default=32, help="Overlap halo margin in pixels")
    args = parser.parse_args()

    print(f"GeoEdge pipeline initialized (sigma={args.sigma}, tile_size={args.tile_size}, halo={args.halo})")

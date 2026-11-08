import os
import sys
import numpy as np

# Add src/python to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src", "python"))

import geoedge_core
from tiling import TiledRasterProcessor
from spectral import compute_ndwi, compute_mndwi


def test_core_execution():
    img = np.random.rand(256, 256).astype(np.float32)
    res = geoedge_core.canny_detect(img, sigma=1.5, use_otsu=True)
    assert res["edges"].shape == (256, 256)
    assert res["low_threshold"] > 0
    assert res["high_threshold"] > res["low_threshold"]
    print("test_core_execution: PASSED")


def test_tiling_execution():
    img = np.random.rand(1500, 1500).astype(np.float32)
    processor = TiledRasterProcessor(tile_size=512, halo=16)
    edges = processor.process_array(img, sigma=1.2, use_otsu=True)
    assert edges.shape == (1500, 1500)
    assert edges.dtype == np.uint8
    print("test_tiling_execution: PASSED")


def test_spectral_indices():
    green = np.full((100, 100), 0.5, dtype=np.float32)
    nir = np.full((100, 100), 0.1, dtype=np.float32)
    ndwi = compute_ndwi(green, nir)
    assert np.all(ndwi > 0.6)  # High water response
    print("test_spectral_indices: PASSED")


if __name__ == "__main__":
    test_core_execution()
    test_tiling_execution()
    test_spectral_indices()
    print("All GeoEdge unit tests PASSED successfully!")

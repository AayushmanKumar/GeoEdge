"""
spectral.py - Multispectral Water Indices for Remote Sensing
Part of GeoEdge High-Performance Pipeline
"""

import numpy as np


def compute_ndwi(green: np.ndarray, nir: np.ndarray, epsilon: float = 1e-6) -> np.ndarray:
    """
    McFeeters (1996) Normalized Difference Water Index:
    NDWI = (Green - NIR) / (Green + NIR)
    Sentinel-2: (B03 - B08) / (B03 + B08)
    Water pixels exhibit positive values (> 0), terrestrial features are negative.
    """
    green_f = green.astype(np.float32)
    nir_f = nir.astype(np.float32)
    numerator = green_f - nir_f
    denominator = green_f + nir_f + epsilon
    ndwi = numerator / denominator
    return np.clip(ndwi, -1.0, 1.0)


def compute_mndwi(green: np.ndarray, swir: np.ndarray, epsilon: float = 1e-6) -> np.ndarray:
    """
    Xu (2006) Modified Normalized Difference Water Index:
    MNDWI = (Green - SWIR) / (Green + SWIR)
    Sentinel-2: (B03 - B11) / (B03 + B11)
    Enhances open water while suppressing built-up urban features.
    """
    green_f = green.astype(np.float32)
    swir_f = swir.astype(np.float32)
    numerator = green_f - swir_f
    denominator = green_f + swir_f + epsilon
    mndwi = numerator / denominator
    return np.clip(mndwi, -1.0, 1.0)

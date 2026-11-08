"""
tiling.py - High-Throughput Memory-Bounded Sliding-Window Chunker
Part of GeoEdge High-Performance Pipeline
"""

import numpy as np
from typing import Tuple, Generator, Optional
try:
    import rasterio
    from rasterio.windows import Window
    HAS_RASTERIO = True
except ImportError:
    HAS_RASTERIO = False

import geoedge_core


class TiledRasterProcessor:
    """
    Processes large spatial rasters in sliding windows with overlap halos
    to maintain strictly bounded peak heap memory (< 250 MB).
    """

    def __init__(self, tile_size: int = 1024, halo: int = 32):
        self.tile_size = tile_size
        self.halo = halo

    def get_tile_coordinates(self, height: int, width: int) -> Generator[Tuple[int, int, int, int, int, int, int, int], None, None]:
        """
        Yields coordinates for each block:
        (r_start, r_end, c_start, c_end, pad_top, pad_bottom, pad_left, pad_right)
        """
        for r in range(0, height, self.tile_size):
            r_end = min(r + self.tile_size, height)
            
            # Tile with halo
            r_halo_start = max(0, r - self.halo)
            r_halo_end = min(height, r_end + self.halo)

            pad_top = r - r_halo_start
            pad_bottom = r_halo_end - r_end

            for c in range(0, width, self.tile_size):
                c_end = min(c + self.tile_size, width)

                c_halo_start = max(0, c - self.halo)
                c_halo_end = min(width, c_end + self.halo)

                pad_left = c - c_halo_start
                pad_right = c_halo_end - c_end

                yield (r, r_end, c, c_end, r_halo_start, r_halo_end, c_halo_start, c_halo_end, pad_top, pad_left)

    def process_array(
        self,
        array: np.ndarray,
        sigma: float = 1.5,
        low_threshold: float = -1.0,
        high_threshold: float = -1.0,
        use_otsu: bool = True
    ) -> np.ndarray:
        """
        Processes a large 2D float32 array block-by-block with halo padding.
        """
        height, width = array.shape
        output_edges = np.zeros((height, width), dtype=np.uint8)

        for (r, r_end, c, c_end, 
             r_h_start, r_h_end, c_h_start, c_h_end, 
             pad_top, pad_left) in self.get_tile_coordinates(height, width):
            
            # Extract tile with halo
            tile = array[r_h_start:r_h_end, c_h_start:c_h_end].astype(np.float32)

            # Pad if at boundary and smaller than expected halo
            h_tile, w_tile = tile.shape

            # Run C++ SIMD Canny core
            res = geoedge_core.canny_detect(
                tile,
                sigma=sigma,
                low_threshold=low_threshold,
                high_threshold=high_threshold,
                use_otsu=use_otsu
            )
            tile_edges = res["edges"]

            # Strip halo
            valid_h = r_end - r
            valid_w = c_end - c
            clean_edges = tile_edges[pad_top : pad_top + valid_h, pad_left : pad_left + valid_w]

            # Place into global map
            output_edges[r:r_end, c:c_end] = clean_edges

        return output_edges

    def process_geotiff(
        self,
        input_path: str,
        output_path: str,
        band_idx: int = 1,
        sigma: float = 1.5,
        use_otsu: bool = True
    ) -> None:
        """
        Streams a GeoTIFF directly from disk chunk-by-chunk without loading full raster to RAM.
        """
        if not HAS_RASTERIO:
            raise ImportError("rasterio is required for process_geotiff.")

        with rasterio.open(input_path) as src:
            meta = src.meta.copy()
            meta.update({
                'count': 1,
                'dtype': 'uint8',
                'nodata': 0
            })

            height, width = src.height, src.width

            with rasterio.open(output_path, 'w', **meta) as dst:
                for (r, r_end, c, c_end,
                     r_h_start, r_h_end, c_h_start, c_h_end,
                     pad_top, pad_left) in self.get_tile_coordinates(height, width):

                    window_halo = Window(c_h_start, r_h_start, c_h_end - c_h_start, r_h_end - r_h_start)
                    tile = src.read(band_idx, window=window_halo).astype(np.float32)

                    res = geoedge_core.canny_detect(tile, sigma=sigma, use_otsu=use_otsu)
                    tile_edges = res["edges"]

                    valid_h = r_end - r
                    valid_w = c_end - c
                    clean_edges = tile_edges[pad_top : pad_top + valid_h, pad_left : pad_left + valid_w]

                    out_window = Window(c, r, valid_w, valid_h)
                    dst.write(clean_edges, 1, window=out_window)

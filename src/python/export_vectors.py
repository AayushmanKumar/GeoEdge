"""
export_vectors.py - Vectorize GeoEdge Raster Boundaries to GeoJSON/Shapefile
Part of GeoEdge High-Performance Pipeline
"""

import os
import json
from typing import Optional
import numpy as np
try:
    import rasterio
    from rasterio.features import shapes
    from shapely.geometry import shape, mapping
    import shapely.ops
    HAS_GEOSPATIAL = True
except ImportError:
    HAS_GEOSPATIAL = False


def raster_edges_to_geojson(
    edge_mask: np.ndarray,
    output_geojson_path: str,
    transform: Optional = None,
    crs: str = "EPSG:32636"
) -> None:
    """
    Vectorizes a binary edge raster into GeoJSON features.
    If geospatial transform is provided, outputs georeferenced coordinates;
    otherwise outputs pixel coordinates.
    """
    if not HAS_GEOSPATIAL:
        # Fallback to pure python json output for pixel coordinates
        height, width = edge_mask.shape
        edge_coords = np.argwhere(edge_mask > 0)
        features = []
        for r, c in edge_coords:
            features.append({
                "type": "Feature",
                "geometry": {
                    "type": "Point",
                    "coordinates": [float(c), float(r)]
                },
                "properties": {"value": 255}
            })
        geojson_data = {
            "type": "FeatureCollection",
            "features": features
        }
        os.makedirs(os.path.dirname(os.path.abspath(output_geojson_path)), exist_ok=True)
        with open(output_geojson_path, "w") as f:
            json.dump(geojson_data, f)
        print(f"Exported {len(features)} vector points to {output_geojson_path}")
        return

    # Extract polygonized shapes from binary mask
    mask = (edge_mask > 0).astype(np.int16)
    results = []
    for geom, val in shapes(mask, mask=mask, transform=transform):
        if val == 1:
            poly = shape(geom)
            boundary = poly.boundary
            if not boundary.is_empty:
                results.append({
                    "type": "Feature",
                    "geometry": mapping(boundary),
                    "properties": {"edge_type": "water_boundary", "crs": str(crs)}
                })

    feature_collection = {
        "type": "FeatureCollection",
        "crs": {
            "type": "name",
            "properties": {"name": f"urn:ogc:def:crs:{crs.replace(':', '::')}"}
        },
        "features": results
    }

    os.makedirs(os.path.dirname(os.path.abspath(output_geojson_path)), exist_ok=True)
    with open(output_geojson_path, "w") as f:
        json.dump(feature_collection, f, indent=2)

    print(f"Successfully exported {len(results)} vector boundary lines to {output_geojson_path}")


if __name__ == "__main__":
    # Test vectorizer on a sample binary array
    sample_edges = np.zeros((100, 100), dtype=np.uint8)
    sample_edges[20:80, 50] = 255  # Vertical line
    out_path = "GeoEdge/data/outputs/test_edges.geojson"
    raster_edges_to_geojson(sample_edges, out_path)

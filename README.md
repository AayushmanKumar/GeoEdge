# GeoEdge: Adaptive Canny Edge Detection for Satellite Imagery

> **CE671: Introduction to Remote Sensing** — IIT Kanpur (Instructor: **Dr. Salil Goel**)  
> **Group 15 Term Project**  
> **Authors:**  
> - **Aayushman Kumar** (Roll No. 230029, Lead)  
> - **Shivakshi** (Roll No. 23118066)  
> - **Rajendra Singh** (Roll No. 261230610)

---

## Overview

**GeoEdge** is an edge detection pipeline designed for automated water–land boundary delineation in Sentinel-2 multispectral satellite imagery. 

While classical spatial filters (Sobel, Prewitt, Roberts, Laplacian) produce thick, noisy, and broken edges, GeoEdge applies the 5-step Canny edge detector enhanced with:
1. **Spectral Enhancement (NDWI):** Uses Normalized Difference Water Index $(B03 - B08) / (B03 + B08)$ to suppress terrestrial background clutter (roads, buildings, fields) before filtering.
2. **Adaptive Otsu Thresholding:** Automatically determines strong and weak hysteresis thresholds from the gradient magnitude histogram, removing manual guesswork.
3. **Memory-Bounded Tiling:** Employs sliding-window chunking ($1024 \times 1024$ pixels) with a 32-pixel overlap halo to prevent boundary seam artifacts, keeping peak memory under **$106\text{ MB}$** even on $100\text{M}+$ pixel granules.
4. **C++20 SIMD Core:** High-performance separable Gaussian blur and Non-Maximum Suppression (NMS) providing a **$4.2\times$ speedup** over standard Python/OpenCV baselines.

---

## Key Experimental Results

Evaluated against the UK Hydrographic Office **Sentinel-2 Water Edges Dataset (SWED)**:

| Metric | Python / OpenCV Baseline | GeoEdge Measured (C++20 SIMD) |
| :--- | :---: | :---: |
| **Ashdod Coastline F1-Score** | $74.6\%$ (raw NIR) | **$91.4\%$ (NDWI + Adaptive Canny)** |
| **Ashdod IoU** | $61.2\%$ | **$84.2\%$** |
| **98-Scene SWED Benchmark** | $0.42$ (raw Sobel) | **$0.809$ mean F1-score** |
| **Runtime (100M+ pixels)** | $47.10\text{ s}$ | **$11.20\text{ s}$ ($4.2\times$ faster)** |
| **Peak Memory Usage** | $1,840\text{ MB}$ (unbounded) | **$105.5\text{ MB}$ ($17\times$ reduction)** |

![GeoEdge Comparison Figure](Reports%20&%20Presentations/figures/fig30_geoedge_pipeline_output.png)
*Visual evaluation on Sentinel-2 SWED imagery: (a) Input NDWI, (b) Classical Sobel filter (thick multi-pixel ridges), (c) GeoEdge Adaptive Canny (thinned 1-pixel boundary), (d) Reference ground-truth coastline.*

---

## Deliverables & Project Structure

```
GeoEdge/
├── README.md                   # Project overview, results, and usage guide
├── CMakeLists.txt              # CMake build configuration for C++ core & pybind11
├── pyproject.toml              # Python package metadata
├── requirements.txt            # Python dependencies (numpy, scipy, opencv, rasterio)
├── src/
│   ├── cpp/                    # C++20 SIMD-vectorized processing core
│   │   ├── include/            # Canny & Otsu header definitions
│   │   └── canny_core.cpp      # Separable Gaussian blur, gradient & NMS kernels
│   ├── bindings/
│   │   └── pybind_wrapper.cpp  # pybind11 module interface
│   └── python/
│       ├── pipeline.py         # End-to-end pipeline orchestrator
│       ├── tiling.py           # Sliding-window raster chunker with 32px halo
│       ├── spectral.py         # NDWI and MNDWI spectral index calculators
│       └── export_vectors.py   # Vector contour and GeoJSON exporter
├── experiments/
│   ├── benchmark_perf.py       # 100M-pixel scalability, throughput & RAM profiler
│   ├── generate_figures.py     # 300 DPI comparison figure generator
│   └── matlab/                 # MATLAB verification scripts for classroom filters
│       ├── README.md           # Instructions for MATLAB scripts
│       ├── canny_swed.m        # Main evaluation script (Ashdod & multi-scene)
│       └── canny_swed_data.m   # Headless export script (CSVs & PNGs)
├── canny_multiple_results/     # Output edge maps, CSVs, and scores across 18 SWED scenes
├── data/                       # Sample outputs and GeoJSON contours
├── Reports & Presentations/
│   ├── Report/
│   │   ├── Canny_Term_Paper_Group15.pdf   # Final term paper report (20 pages A4)
│   │   └── Canny_Term_Paper_Group15.docx  # Editable Word report
│   ├── presentation/
│   │   ├── Canny Edge Detection Filter Group 15 Presentation.pptx  # 10 slides
│   │   ├── Canny Edge Detection Filter Group 15 Presentation.pdf   # Slide deck PDF
│   │   └── SPEAKER_NOTES.md               # 15-min delivery plan & Q&A guide
│   ├── figures/                # Output comparison figures (300 DPI)
│   └── filter_comparison.md    # Detailed classroom filter analysis
└── tests/
    └── test_pipeline.py        # Unit test suite for C++ core, tiling, and spectral indices
```

---

## Usage

### 1. Environment Setup

```bash
# Clone repository and enter directory
cd GeoEdge

# (Optional) Create and activate virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

### 2. Building the C++ Core Extension

The precompiled binary `geoedge_core.*.so` is already included in `src/python/`. To recompile from source:

```bash
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
cp geoedge_core.*.so ../src/python/
cd ..
```

### 3. Running Unit Tests

Verify the C++ engine, sliding-window chunker, and spectral indices:

```bash
python3 tests/test_pipeline.py
```

### 4. Running the GeoEdge Pipeline

Run the pipeline with configurable parameters:

```bash
python3 src/python/pipeline.py --sigma 1.5 --tile-size 1024 --halo 32
```

### 5. Running the Scalability & Memory Benchmark

Benchmark throughput, runtime, and peak heap RAM on a 100-million-pixel raster:

```bash
python3 experiments/benchmark_perf.py
```

### 6. Exporting Vector Contours (GeoJSON)

Extract vector coastline coordinates from binary edge rasters:

```bash
python3 src/python/export_vectors.py
```

### 7. Running MATLAB Filter Comparisons

To reproduce the classroom filter comparison (Roberts, Sobel, Prewitt, Laplacian, LoG, Canny):
1. Open MATLAB and navigate to `experiments/matlab/`.
2. Run `canny_swed.m` to generate figures and evaluation metrics.

---

## References

1. Canny, J. (1986). *A Computational Approach to Edge Detection*. IEEE TPAMI, 8(6), 679–698.
2. McFeeters, S. K. (1996). *The use of the Normalized Difference Water Index (NDWI) in the delineation of open water features*. Int. J. Remote Sensing, 17(7), 1425–1432.
3. Seale, C., Redfern, T., & Chatfield, P. (2022). *Sentinel-2 Water Edges Dataset (SWED)*. UK Hydrographic Office.
4. Gonzalez, R. C., & Woods, R. E. (2018). *Digital Image Processing* (4th ed.). Pearson.

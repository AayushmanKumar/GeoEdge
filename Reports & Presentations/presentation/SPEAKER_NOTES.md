# GeoEdge Presentation Speaker Notes & Delivery Plan

> **Course:** CE671 Introduction to Remote Sensing (IIT Kanpur)  
> **Instructor:** Dr. Salil Goel  
> **Presentation Duration:** 15 Minutes (Strictly enforced: 5 min per speaker) + 5 Minutes Q&A  
> **Slide Deck:** `Canny Edge Detection Filter Group 15 Presentation.pptx` (10 Slides)

---

## Presentation Timing & Speaker Roles

```
  00:00 - 05:00                     05:00 - 10:00                     10:00 - 15:00
┌────────────────────────────────┬─────────────────────────────────┬────────────────────────────────┐
│ Part 1: Shivakshi              │ Part 2: Rajendra                │ Part 3: Aayushman              │
│ • Slide 1: Title & Outline     │ • Slide 5: NDWI Remote Sensing  │ • Slide 9: GeoEdge Scalability │
│ • Slide 2: Edges & Coastlines  │ • Slide 6: SWED Data & Method   │ • Slide 10: Conclusions        │
│ • Slide 3: Classical Filters   │ • Slide 7: Ashdod Results       │ • Q&A Session Lead             │
│ • Slide 4: Canny 1986 (5 steps)│ • Slide 8: Multi-scene Benchmark│                                │
└────────────────────────────────┴─────────────────────────────────┴────────────────────────────────┘
```

---

## Slide-by-Slide Delivery Script

### Part 1: Fundamentals of Edge Detection & Canny (Shivakshi, 00:00 – 05:00)

* **Slide 1: Title & Outline (30s)**
  > *"Good morning Sir and classmates. We are Group 15, and today we present our CE671 term paper: 'Canny Edge Detection Filter – Concept, Development, Use and Application on Satellite Imagery.' Our presentation is structured into three parts: basic concept and classical filters, remote sensing integration with SWED benchmark results, and high-throughput scalable engineering."*

* **Slide 2: Edges and the Coastline Problem (90s)**
  > *"An edge in an image is a rapid change in brightness over a short spatial distance. In textbook image processing, we think of step edges. But in satellite imagery, edges are ramp transitions spanning multiple 10-meter pixels due to sensor point spread functions and mixed land-water pixels. Delineating water boundaries is crucial for flood mapping, navigation, and coastal erosion monitoring. However, standard edge detectors get confused: urban roofs, roads, and field borders produce sharp edges, while boat wakes and waves create false edges inside the water. Our goal is to explain how Canny solves these issues and evaluate it on real Sentinel-2 satellite data."*

* **Slide 3: Classical Filters and Their Limits (75s)**
  > *"Spatial edge filtering works by sliding a small zero-sum kernel over the image. Over flat water, the sum of products is zero. Across a land-water transition, the gradient magnitude G is high. The classical filters taught in our course—Roberts (1963), Prewitt (1970), Sobel (1968), and the Laplacian—only calculate gradient strength. They produce thick multi-pixel bands, are very sensitive to sensor noise, and break wherever the contrast is weak. They don't give a thin, continuous 1-pixel boundary."*

* **Slide 4: Canny’s Approach (1986) (105s)**
  > *"In 1986, John Canny developed an optimal edge detector based on three mathematical criteria: good detection (high SNR), good localization (marking edges close to their true center), and a single response per edge. He broke the problem into five clear steps: (1) Gaussian smoothing with parameter sigma to suppress noise; (2) Sobel gradient calculation for strength and direction; (3) Non-Maximum Suppression (NMS), which thins wide gradient bands into clean 1-pixel ridges by checking neighbors along the gradient vector; (4) Double thresholding into strong and weak candidates; and (5) Hysteresis tracking, which preserves weak edges only if they are connected to strong ones. This prevents edge fragmentation."*
  >
  > *Handover: "Now Rajendra will present how we integrate remote sensing domain knowledge (NDWI) and our benchmark results."*

---

### Part 2: Remote Sensing Integration & Experimental Results (Rajendra, 05:00 – 10:00)

* **Slide 5: Making Canny Find Water: NDWI (75s)**
  > *"Canny is a generic image processing filter—it detects brightness changes without knowing what water is. On raw grayscale images, it marks docks, roads, and rooftops. To make it focus strictly on coastlines, we use remote sensing domain physics: water absorbs near-infrared (NIR) light almost completely, while land reflects it strongly. By calculating McFeeters' Normalized Difference Water Index (B03 Green minus B08 NIR over their sum) before filtering, land clutter is suppressed, making the water-land boundary the primary gradient in the scene. We also tested MNDWI using SWIR (B11), but its 20-meter resolution made the coastline blocky compared to the 10-meter native NDWI."*

* **Slide 6: Data and Evaluation Method (75s)**
  > *"We evaluated the filters against the Sentinel-2 Water Edges Dataset (SWED) published by the UK Hydrographic Office. In Part A, we performed exhaustive parameter sweeps on the Ashdod Port test scene with a hand-drawn ground-truth mask. In Part B, we tested all 98 scenes spanning diverse coastal geomorphologies. We adopted a strict 2-pixel (20-meter) spatial buffer tolerance to compute Precision, Recall, and F1-score against the ground-truth waterline."*

* **Slide 7: Results: Six Filters on Ashdod (75s)**
  > *"On Ashdod Grayscale, Canny achieved the highest performance with an F1-score of 0.92 (Precision 0.94, Recall 0.91). Roberts, Sobel, and Prewitt scored between 0.80 and 0.82, suffering from broken lines along port docks and thick edges. The Laplacian collapsed to an F1 of 0.43 because second derivatives severely amplify noise (Recall 0.98, but Precision only 0.28). We also analyzed blur: sigma = 1 kept too much urban noise, sigma = 3 was optimal, and sigma = 4 blurred both sides of the narrow breakwater into one."*

* **Slide 8: Results: Effect of Input, Ashdod and 98 Scenes (75s)**
  > *"Across the entire 98-scene benchmark, NDWI boosted classical filters like Sobel and Prewitt from ~0.42 up to 0.76. Canny on NDWI achieved the highest global score of 0.809 mean F1. On clean sandy beaches, Canny reached 0.94 F1, and on turbid river mouths, 0.82 F1. This proves that combining spectral physics with Canny's morphological edge tracking delivers robust, consistent boundaries across varied terrains."*
  >
  > *Handover: "Now Aayushman will present GeoEdge's large-raster architecture and engineering benchmarks."*

---

### Part 3: High-Throughput Architecture, Scalability & Conclusions (Aayushman, 10:00 – 15:00)

* **Slide 9: GeoEdge: Canny on Large Images (90s)**
  > *"A full Sentinel-2 granule exceeds 10,980 by 10,980 pixels across multiple bands (over 1.2 GB uncompressed). Attempting to process entire rasters at once in standard Python causes memory blowup and crashes typical lab machines. In GeoEdge, we solved this through three systems engineering techniques: First, memory-bounded sliding-window chunking (1024 × 1024 blocks) with a 32-pixel overlap halo. The halo ensures convolution kernels and hysteresis tracking have complete support across block seams without cutting edges. Second, an optimized C++20 core with SIMD auto-vectorization and OpenMP multithreading, exposed to Python via pybind11. Third, adaptive Otsu thresholding directly on the gradient histogram, eliminating manual parameter guesswork. On a 100-million-pixel benchmark raster, GeoEdge achieved a 4.2× speedup (11.2 seconds vs 47.1 seconds) and reduced peak RAM usage by 17× (bounded to 105.5 MB vs 1.84 GB)."*

* **Slide 10: Conclusions & Takeaways (90s)**
  > *"To summarize our key findings: (1) Canny is the best overall filter, turning wide, noisy satellite gradients into crisp 1-pixel boundaries with 0.92 F1 on Ashdod and 0.809 across 98 SWED scenes; (2) Domain knowledge is essential—spectral enhancement via NDWI suppresses terrestrial noise and makes simple filters competitive; (3) Tiled processing with boundary halos makes Canny computationally feasible on massive gigapixel satellite rasters within strict memory limits. GeoEdge provides an interpretable, lightweight, and fast alternative to heavy deep-learning networks for coastal monitoring. Thank you for your time. We are now open for questions."*

---

## Rapid-Fire Q&A Preparation (Anticipated Questions from Prof. Salil Goel)

1. **Q: Why does the Laplacian filter have such a low precision (0.28) on Ashdod?**  
   * **Answer:** The Laplacian uses second-order derivatives ($\nabla^2 I$). Second derivatives amplify high-frequency noise quadratically compared to first-order gradients. Without directional filtering and non-maximum suppression, every slight intensity variation and building edge produces false zero-crossings across the entire scene.

2. **Q: Why does NDWI outperform MNDWI for Sentinel-2 coastline extraction?**  
   * **Answer:** Sentinel-2 Band 8 (broad NIR) has a native spatial resolution of 10 meters, matching Blue, Green, and Red. In contrast, Band 11 (SWIR) used in MNDWI has a native resolution of 20 meters. Resampling SWIR to 10 meters creates stepped, pixelated boundaries along waterlines, degrading edge localization.

3. **Q: How does GeoEdge prevent edge artifacts and disconnections across tile boundaries?**  
   * **Answer:** Each 1024 × 1024 tile is read with a 32-pixel overlap halo on all four sides. Gaussian smoothing and 8-connected hysteresis tracking evaluate pixels within the halo buffer. After processing, the 32-pixel halo margin is trimmed before writing to the output GeoTIFF, ensuring mathematical continuity and no visible seams.

4. **Q: How does Canny compare to modern deep learning models (e.g. U-Net) on the SWED dataset?**  
   * **Answer:** In the SWED paper (Seale et al., 2022), U-Net achieved ~0.82 IoU, but required multi-hour GPU training and gigabytes of VRAM. GeoEdge achieves comparable accuracy (84.2% IoU, 91.4% F1 on clear coastlines) on standard CPU hardware in 11.2 seconds, with complete mathematical interpretability and zero training requirements.

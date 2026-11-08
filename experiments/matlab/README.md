# MATLAB scripts (Part A: Canny vs classical filters on SWED)

Use canny_swed.m (main, recommended)
- Full script: all paper figures, scores for 6 filters x 3 inputs
- Section 7: set TEST_DIR to run every SWED test image with fixed settings (useful for Part B)

canny_swed_data.m (light version)
- No figures; saves CSV and PNG only (made because MATLAB Online had trouble saving figures)
- Also saves the full Canny sweep (210 runs) and best threshold per sigma (Table 3 in report)

To run on a new scene: change IMG_FILE, LBL_FILE and OUT_DIR at the top of the script.
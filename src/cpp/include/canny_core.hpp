#pragma once

#include <vector>
#include <cstdint>
#include <utility>

namespace geoedge {

/**
 * @brief Complete Canny Edge Detection Pipeline parameters and return results.
 */
struct CannyParams {
    float sigma = 1.5f;
    float low_threshold = -1.0f;   // If < 0, Otsu thresholding is used
    float high_threshold = -1.0f;  // If < 0, Otsu thresholding is used
    bool use_otsu = true;
};

struct CannyResult {
    std::vector<uint8_t> edge_map;
    float computed_low_threshold;
    float computed_high_threshold;
    int height;
    int width;
};

/**
 * @brief Generates 1D normalized Gaussian kernel.
 */
std::vector<float> create_gaussian_kernel_1d(float sigma, int& radius);

/**
 * @brief High-performance 2D separable Gaussian smoothing.
 */
void separable_gaussian_blur(
    const float* input,
    float* output,
    int height,
    int width,
    float sigma
);

/**
 * @brief Vectorized Sobel spatial gradient computation.
 * Computes magnitude and 4-direction sector orientation (0: E-W, 1: NE-SW, 2: N-S, 3: NW-SE).
 */
void compute_sobel_gradients(
    const float* smoothed,
    float* magnitude,
    uint8_t* orientation,
    int height,
    int width
);

/**
 * @brief Non-Maximum Suppression (thins edges along gradient normal to 1-pixel width).
 */
void non_maximum_suppression(
    const float* magnitude,
    const uint8_t* orientation,
    float* nms_output,
    int height,
    int width
);

/**
 * @brief Dual-threshold classification and 8-connected edge tracking via hysteresis.
 */
void hysteresis_edge_tracking(
    const float* nms_output,
    uint8_t* edge_map,
    int height,
    int width,
    float low_thresh,
    float high_thresh
);

/**
 * @brief Full end-to-end GeoEdge Canny execution.
 */
CannyResult run_canny_pipeline(
    const float* input,
    int height,
    int width,
    const CannyParams& params
);

} // namespace geoedge

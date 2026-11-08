#include "canny_core.hpp"
#include "otsu.hpp"

#include <cmath>
#include <vector>
#include <queue>
#include <algorithm>
#include <cstring>
#include <omp.h>

namespace geoedge {

std::vector<float> create_gaussian_kernel_1d(float sigma, int& radius) {
    radius = static_cast<int>(std::ceil(3.0f * sigma));
    if (radius < 1) radius = 1;
    int size = 2 * radius + 1;
    std::vector<float> kernel(size);

    float sum = 0.0f;
    float two_sigma_sq = 2.0f * sigma * sigma;
    for (int i = -radius; i <= radius; ++i) {
        float val = std::exp(-static_cast<float>(i * i) / two_sigma_sq);
        kernel[i + radius] = val;
        sum += val;
    }

    // Normalize
    for (int i = 0; i < size; ++i) {
        kernel[i] /= sum;
    }
    return kernel;
}

void separable_gaussian_blur(
    const float* input,
    float* output,
    int height,
    int width,
    float sigma
) {
    if (sigma <= 0.01f) {
        std::memcpy(output, input, height * width * sizeof(float));
        return;
    }

    int radius = 0;
    std::vector<float> kernel = create_gaussian_kernel_1d(sigma, radius);

    std::vector<float> temp(height * width);

    // 1. Horizontal 1D pass
    #pragma omp parallel for schedule(static)
    for (int r = 0; r < height; ++r) {
        const float* in_row = input + r * width;
        float* temp_row = temp.data() + r * width;

        for (int c = 0; c < width; ++c) {
            float sum = 0.0f;
            #pragma omp simd reduction(+:sum)
            for (int k = -radius; k <= radius; ++k) {
                int col_idx = c + k;
                // Mirrored / reflected boundary
                if (col_idx < 0) col_idx = -col_idx;
                else if (col_idx >= width) col_idx = 2 * width - 2 - col_idx;
                if (col_idx < 0) col_idx = 0;
                if (col_idx >= width) col_idx = width - 1;

                sum += in_row[col_idx] * kernel[k + radius];
            }
            temp_row[c] = sum;
        }
    }

    // 2. Vertical 1D pass
    #pragma omp parallel for schedule(static)
    for (int r = 0; r < height; ++r) {
        float* out_row = output + r * width;

        for (int c = 0; c < width; ++c) {
            float sum = 0.0f;
            #pragma omp simd reduction(+:sum)
            for (int k = -radius; k <= radius; ++k) {
                int row_idx = r + k;
                // Mirrored / reflected boundary
                if (row_idx < 0) row_idx = -row_idx;
                else if (row_idx >= height) row_idx = 2 * height - 2 - row_idx;
                if (row_idx < 0) row_idx = 0;
                if (row_idx >= height) row_idx = height - 1;

                sum += temp[row_idx * width + c] * kernel[k + radius];
            }
            out_row[c] = sum;
        }
    }
}

void compute_sobel_gradients(
    const float* smoothed,
    float* magnitude,
    uint8_t* orientation,
    int height,
    int width
) {
    std::memset(magnitude, 0, height * width * sizeof(float));
    std::memset(orientation, 0, height * width * sizeof(uint8_t));

    const float pi = 3.14159265358979323846f;
    const float rad_to_deg = 180.0f / pi;

    #pragma omp parallel for schedule(static)
    for (int r = 1; r < height - 1; ++r) {
        const float* row_prev = smoothed + (r - 1) * width;
        const float* row_curr = smoothed + r * width;
        const float* row_next = smoothed + (r + 1) * width;

        float* mag_row = magnitude + r * width;
        uint8_t* ori_row = orientation + r * width;

        #pragma omp simd
        for (int c = 1; c < width - 1; ++c) {
            // Sobel X kernel:
            // -1  0  1
            // -2  0  2
            // -1  0  1
            float gx = (row_prev[c + 1] - row_prev[c - 1]) +
                       2.0f * (row_curr[c + 1] - row_curr[c - 1]) +
                       (row_next[c + 1] - row_next[c - 1]);

            // Sobel Y kernel:
            //  1  2  1
            //  0  0  0
            // -1 -2 -1
            float gy = (row_prev[c - 1] - row_next[c - 1]) +
                       2.0f * (row_prev[c] - row_next[c]) +
                       (row_prev[c + 1] - row_next[c + 1]);

            float mag = std::sqrt(gx * gx + gy * gy);
            mag_row[c] = mag;

            // Compute angle in degrees: [0, 180)
            float angle = std::atan2(gy, gx) * rad_to_deg;
            if (angle < 0.0f) angle += 180.0f;

            // Quantize into 4 directions:
            // 0: East-West (0 deg or 180 deg) -> [-22.5, 22.5) or [157.5, 180]
            // 1: Northeast-Southwest (45 deg) -> [22.5, 67.5)
            // 2: North-South (90 deg)         -> [67.5, 112.5)
            // 3: Northwest-Southeast (135 deg) -> [112.5, 157.5)
            uint8_t dir = 0;
            if (angle >= 22.5f && angle < 67.5f) {
                dir = 1;
            } else if (angle >= 67.5f && angle < 112.5f) {
                dir = 2;
            } else if (angle >= 112.5f && angle < 157.5f) {
                dir = 3;
            } else {
                dir = 0;
            }
            ori_row[c] = dir;
        }
    }
}

void non_maximum_suppression(
    const float* magnitude,
    const uint8_t* orientation,
    float* nms_output,
    int height,
    int width
) {
    std::memset(nms_output, 0, height * width * sizeof(float));

    #pragma omp parallel for schedule(static)
    for (int r = 1; r < height - 1; ++r) {
        const float* mag_prev = magnitude + (r - 1) * width;
        const float* mag_curr = magnitude + r * width;
        const float* mag_next = magnitude + (r + 1) * width;
        const uint8_t* ori_curr = orientation + r * width;
        float* nms_row = nms_output + r * width;

        for (int c = 1; c < width - 1; ++c) {
            float m = mag_curr[c];
            if (m <= 1e-5f) continue;

            uint8_t dir = ori_curr[c];
            float p1 = 0.0f, p2 = 0.0f;

            switch (dir) {
                case 0: // E-W (Horizontal): Compare with left and right
                    p1 = mag_curr[c - 1];
                    p2 = mag_curr[c + 1];
                    break;
                case 1: // NE-SW (Diagonal 45): Compare with top-right and bottom-left
                    p1 = mag_prev[c + 1];
                    p2 = mag_next[c - 1];
                    break;
                case 2: // N-S (Vertical): Compare with top and bottom
                    p1 = mag_prev[c];
                    p2 = mag_next[c];
                    break;
                case 3: // NW-SE (Diagonal 135): Compare with top-left and bottom-right
                    p1 = mag_prev[c - 1];
                    p2 = mag_next[c + 1];
                    break;
            }

            if (m >= p1 && m >= p2) {
                nms_row[c] = m;
            } else {
                nms_row[c] = 0.0f;
            }
        }
    }
}

void hysteresis_edge_tracking(
    const float* nms_output,
    uint8_t* edge_map,
    int height,
    int width,
    float low_thresh,
    float high_thresh
) {
    std::memset(edge_map, 0, height * width * sizeof(uint8_t));

    // Internal state: 0 = non-edge, 1 = weak edge, 2 = strong edge
    std::vector<uint8_t> state(height * width, 0);
    std::vector<int> strong_indices;
    strong_indices.reserve(height * width / 20);

    for (int i = 0; i < height * width; ++i) {
        float val = nms_output[i];
        if (val >= high_thresh) {
            state[i] = 2;
            strong_indices.push_back(i);
        } else if (val >= low_thresh) {
            state[i] = 1;
        }
    }

    // 8-connectivity offsets
    const int dr[8] = {-1, -1, -1,  0, 0,  1, 1, 1};
    const int dc[8] = {-1,  0,  1, -1, 1, -1, 0, 1};

    // Queue for BFS edge tracking
    std::queue<int> q;
    for (int idx : strong_indices) {
        edge_map[idx] = 255;
        q.push(idx);
    }

    while (!q.empty()) {
        int curr = q.front();
        q.pop();

        int r = curr / width;
        int c = curr % width;

        for (int k = 0; k < 8; ++k) {
            int nr = r + dr[k];
            int nc = c + dc[k];

            if (nr >= 0 && nr < height && nc >= 0 && nc < width) {
                int n_idx = nr * width + nc;
                if (state[n_idx] == 1 && edge_map[n_idx] == 0) {
                    edge_map[n_idx] = 255;
                    q.push(n_idx);
                }
            }
        }
    }
}

CannyResult run_canny_pipeline(
    const float* input,
    int height,
    int width,
    const CannyParams& params
) {
    size_t num_pixels = static_cast<size_t>(height) * width;
    std::vector<float> smoothed(num_pixels);
    std::vector<float> magnitude(num_pixels);
    std::vector<uint8_t> orientation(num_pixels);
    std::vector<float> nms_output(num_pixels);
    std::vector<uint8_t> edge_map(num_pixels);

    // 1. Separable Gaussian smoothing
    separable_gaussian_blur(input, smoothed.data(), height, width, params.sigma);

    // 2. Vectorized Sobel gradients
    compute_sobel_gradients(smoothed.data(), magnitude.data(), orientation.data(), height, width);

    // 3. Non-Maximum Suppression
    non_maximum_suppression(magnitude.data(), orientation.data(), nms_output.data(), height, width);

    // 4. Threshold determination
    float low_t = params.low_threshold;
    float high_t = params.high_threshold;

    if (params.use_otsu || high_t <= 0.0f) {
        auto [t_low, t_high] = compute_otsu_thresholds(nms_output.data(), num_pixels);
        low_t = t_low;
        high_t = t_high;
    } else if (low_t <= 0.0f) {
        low_t = 0.4f * high_t;
    }

    // 5. Hysteresis edge tracking
    hysteresis_edge_tracking(nms_output.data(), edge_map.data(), height, width, low_t, high_t);

    CannyResult result;
    result.edge_map = std::move(edge_map);
    result.computed_low_threshold = low_t;
    result.computed_high_threshold = high_t;
    result.height = height;
    result.width = width;
    return result;
}

} // namespace geoedge

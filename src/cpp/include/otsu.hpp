#pragma once

#include <vector>
#include <cmath>
#include <algorithm>
#include <cstdint>

namespace geoedge {

/**
 * @brief Computes Otsu's optimal threshold on gradient magnitude data.
 * Minimizes intra-class variance (or maximizes inter-class variance).
 * 
 * @param grad_mag Pointer to gradient magnitude array.
 * @param size Number of elements.
 * @param num_bins Number of histogram bins (default: 256).
 * @return std::pair<float, float> Pair of {T_low, T_high}.
 */
inline std::pair<float, float> compute_otsu_thresholds(
    const float* grad_mag, 
    size_t size, 
    int num_bins = 256) 
{
    float min_val = 1e9f;
    float max_val = -1e9f;

    // Find min and max of non-zero gradient magnitudes
    size_t non_zero_count = 0;
    for (size_t i = 0; i < size; ++i) {
        float val = grad_mag[i];
        if (val > 1e-5f) {
            if (val < min_val) min_val = val;
            if (val > max_val) max_val = val;
            non_zero_count++;
        }
    }

    if (non_zero_count == 0 || max_val <= min_val) {
        return {0.05f, 0.15f}; // Fallback default thresholds
    }

    // Build histogram
    std::vector<double> hist(num_bins, 0.0);
    double bin_width = static_cast<double>(max_val - min_val) / num_bins;

    for (size_t i = 0; i < size; ++i) {
        float val = grad_mag[i];
        if (val > min_val) {
            int bin = static_cast<int>((val - min_val) / bin_width);
            if (bin >= num_bins) bin = num_bins - 1;
            hist[bin]++;
        }
    }

    // Otsu's algorithm on normalized histogram
    double total_pixels = static_cast<double>(non_zero_count);
    double sum = 0.0;
    for (int i = 0; i < num_bins; ++i) {
        sum += i * (hist[i] / total_pixels);
    }

    double sumB = 0.0;
    double wB = 0.0;
    double max_var = 0.0;
    int best_thresh_bin = 0;

    for (int i = 0; i < num_bins; ++i) {
        wB += hist[i] / total_pixels;
        if (wB == 0.0) continue;
        double wF = 1.0 - wB;
        if (wF == 0.0) break;

        sumB += i * (hist[i] / total_pixels);
        double mB = sumB / wB;
        double mF = (sum - sumB) / wF;

        double between_var = wB * wF * (mB - mF) * (mB - mF);
        if (between_var > max_var) {
            max_var = between_var;
            best_thresh_bin = i;
        }
    }

    float t_high = min_val + static_cast<float>(best_thresh_bin * bin_width);
    float t_low = 0.4f * t_high;

    return {t_low, t_high};
}

} // namespace geoedge

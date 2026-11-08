#include <pybind11/pybind11.h>
#include <pybind11/numpy.h>
#include <pybind11/stl.h>

#include "canny_core.hpp"

namespace py = pybind11;

/**
 * @brief Python wrapper accepting a 2D float32 NumPy array and returning a binary uint8 edge map.
 */
py::dict canny_detect(
    py::array_t<float, py::array::c_style | py::array::forcecast> input_array,
    float sigma = 1.5f,
    float low_threshold = -1.0f,
    float high_threshold = -1.0f,
    bool use_otsu = true
) {
    py::buffer_info buf = input_array.request();

    if (buf.ndim != 2) {
        throw std::runtime_error("Input array must be 2-dimensional (H, W).");
    }

    int height = static_cast<int>(buf.shape[0]);
    int width = static_cast<int>(buf.shape[1]);

    const float* ptr = static_cast<const float*>(buf.ptr);

    geoedge::CannyParams params;
    params.sigma = sigma;
    params.low_threshold = low_threshold;
    params.high_threshold = high_threshold;
    params.use_otsu = use_otsu;

    geoedge::CannyResult res = geoedge::run_canny_pipeline(ptr, height, width, params);

    // Create 2D NumPy array for the output edge map
    py::array_t<uint8_t> out_edges({height, width});
    py::buffer_info out_buf = out_edges.request();
    std::memcpy(out_buf.ptr, res.edge_map.data(), height * width * sizeof(uint8_t));

    py::dict output;
    output["edges"] = out_edges;
    output["low_threshold"] = res.computed_low_threshold;
    output["high_threshold"] = res.computed_high_threshold;
    output["height"] = height;
    output["width"] = width;

    return output;
}

PYBIND11_MODULE(geoedge_core, m) {
    m.doc() = "GeoEdge High-Performance C++20 SIMD Canny Edge Detection Core";
    m.def("canny_detect", &canny_detect,
          py::arg("image"),
          py::arg("sigma") = 1.5f,
          py::arg("low_threshold") = -1.0f,
          py::arg("high_threshold") = -1.0f,
          py::arg("use_otsu") = true,
          "Run SIMD-accelerated Canny edge detector on a 2D float32 image array.");
}

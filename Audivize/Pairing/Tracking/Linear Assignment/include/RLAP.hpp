#pragma once
#include <cstdint>

size_t solve_rlapf(size_t numrows, size_t numcols,
                   const float* cost, bool maximize,
                   size_t* rowsol, size_t* colsol) noexcept;

size_t solve_rlap(size_t numrows, size_t numcols,
                  const double* cost, bool maximize,
                  size_t* rowsol, size_t* colsol) noexcept;


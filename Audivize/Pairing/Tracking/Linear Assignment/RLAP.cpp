//
//  lapjv.cpp
//  ASD Prototype
//
//  Created by Benjamin Lee on 6/17/25.
//

#include <memory>
#include <cmath>
#include "RLAP.hpp"
#include "CrouseSAP.h"


size_t solve_rlapf(size_t numrows, size_t numcols,
                   const float* cost, bool maximize,
                   size_t* rowsol, size_t* colsol) noexcept {
    return solve_rectangular_linear_assignment<size_t, float>(numrows,
                                                              numcols,
                                                              cost,
                                                              maximize,
                                                              rowsol,
                                                              colsol);
}

size_t solve_rlap(size_t numrows, size_t numcols,
                  const double* cost, bool maximize,
                  size_t* rowsol, size_t* colsol) noexcept {
    return solve_rectangular_linear_assignment<size_t, double>(numrows,
                                                               numcols,
                                                               cost,
                                                               maximize,
                                                               rowsol,
                                                               colsol);
}

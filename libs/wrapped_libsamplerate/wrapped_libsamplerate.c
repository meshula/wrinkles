#include <stdbool.h>
#define PACKAGE "ls-lsr"
#define VERSION "1.0"
#define ENABLE_SINC_BEST_CONVERTER
#define ENABLE_SINC_MEDIUM_CONVERTER
#define ENABLE_SINC_FAST_CONVERTER
#include "samplerate.c"
#include "src_linear.c"
#include "src_sinc.c"
#include "src_zoh.c"

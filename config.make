#
# This file contains makefile configuration options for Oolite builds
#
# This file is sourced by both GNUmakefile and Makefile
#
# Any options can be overridden on the command-line:
# $ make debug=yes DOCKING_CLEARANCE=no
# $ make -f Makefile LIBJS_OPT=yes
#

VERBOSE                        = yes
CP                             = cp

# Setting the build parameters independently. We need everything set as below for the full test release configuration.
BUILD_WITH_DEBUG_FUNCTIONALITY = yes
NO_SHADERS                     = no
ESPEAK                         = yes
OO_CHECK_GL_HEAVY              = no
OO_EXCLUDE_DEBUG_SUPPORT       = no
OO_OXP_VERIFIER_ENABLED        = yes
OO_LOCALIZATION_TOOLS          = yes
DEBUG_GRAPHVIZ                 = yes
OO_JAVASCRIPT_TRACE            = yes

#!/usr/bin/env python3

import platform

all_targets = "..."
# all cxx buildable targets
cxx_targets = "kind('cxx_binary|cxx_library|cxx_test', '...')"

# all the buildable targets - not prebuilt (should have a compilation database)
buildable_targets = "kind('cxx_binary|cxx_library|cxx_test', '...') - kind('prebuilt_cxx_library', '...')"

# the default most code should use is the platform filtered buildable targets:
default_targets = buildable_targets

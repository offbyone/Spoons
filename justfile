# Spoons build configuration
ZIPDIR := "Spoons"
SRCDIR := "Source"

# Default recipe: build all spoons
default: build-all

# Build all spoon zip files
build-all: (_ensure-zipdir)
    #!/usr/bin/env bash
    set -euo pipefail
    for spoon in {{SRCDIR}}/*.spoon; do
        if [ -d "$spoon" ]; then
            name=$(basename "$spoon")
            just build-spoon "$name"
        fi
    done

# Build a specific spoon zip file
build-spoon SPOON: (_ensure-zipdir)
    #!/usr/bin/env bash
    set -euo pipefail
    zipfile="{{ZIPDIR}}/{{SPOON}}.zip"
    rm -f "$zipfile"
    cd {{SRCDIR}} && /usr/bin/zip -9 -r "../$zipfile" "{{SPOON}}"
    echo "Built $zipfile"

# Clean all built zip files
clean:
    rm -f {{ZIPDIR}}/*.zip

# Ensure Spoons directory exists
_ensure-zipdir:
    @mkdir -p {{ZIPDIR}}

# List all available spoons
list:
    #!/usr/bin/env bash
    for spoon in {{SRCDIR}}/*.spoon; do
        if [ -d "$spoon" ]; then
            basename "$spoon"
        fi
    done

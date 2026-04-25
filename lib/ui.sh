#!/usr/bin/env bash
# =============================================================================
#  lib/ui.sh  —  Terminal UI primitives
#
#  Breadcrumb navigation, styled output, and confirmation helpers.
#  Every function here is pure UI — no database calls.
#
#  DEPENDENCIES: gum
# =============================================================================

declare -a MENU_BREADCRUMB=("Main")

push_breadcrumb() { MENU_BREADCRUMB+=("$1"); }
pop_breadcrumb()  { [[ ${#MENU_BREADCRUMB[@]} -gt 1 ]] && unset 'MENU_BREADCRUMB[-1]'; }

section_header() {
    local crumb
    crumb=$(IFS=" > "; echo "${MENU_BREADCRUMB[*]}")
    gum style \
        --border normal \
        --margin "1" \
        --padding "1 2" \
        --border-foreground 008F11 \
        --bold "$crumb > $1"
}

info()    { gum style --foreground 244 "info:  $*";    }
success() { gum style --foreground 76  "OK $*";        }
error()   { gum style --foreground 196 "ERR $*" >&2;   }
warn()    { gum style --foreground 214 "WARN $*";      }

pause() {
    gum style --foreground 244 "Press ENTER to continue..."
    read -r
}

confirm() {
    gum confirm --default=false --timeout=30s -- "$1" || return 1
}

require() {
    command -v "$1" &>/dev/null || {
        echo "Required command not found: $1" >&2
        exit 1
    }
}

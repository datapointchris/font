#!/usr/bin/env bash
# Font sync library - modular, testable functions
# Each function has a single responsibility and can be tested independently

set -euo pipefail

# Directories and files
FONT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
FONT_APP_DIR="$(cd "$FONT_LIB_DIR/.." && pwd)"
PREVIEW_TEXT_FILE="$FONT_APP_DIR/data/preview-text.txt"
CODE_FONTS_DIR="${CODE_FONTS_DIR:-$HOME/Documents/code_fonts}"
PREVIEW_CACHE_DIR="${PREVIEW_CACHE_DIR:-$HOME/.cache/font/previews}"

# ==============================================================================
# CORE FUNCTIONS - Each can be tested independently
# ==============================================================================

FONT_REGISTRY_FILE="$FONT_APP_DIR/data/font-registry.json"

# List managed fonts from the registry
# Returns: One font family name per line (only managed: true entries)
list_fonts() {
  jq -r 'to_entries[] | select(.value.managed == true) | .key' "$FONT_REGISTRY_FILE" | sort
}

# Get the file path for a font by family name
# Args: $1 - font family name
# Returns: Absolute path to font file (prefers Regular/Normal style)
# Exit: 0 if found, 1 if not found
get_font_file_path() {
  local font_name="$1"
  local font_file

  # Use fc-list to find the font file, preferring Regular/Normal styles
  # Format: /path/to/font.ttf: Family Name:style=Style Name

  # Special handling for fonts that render too dim with Regular weight
  # Iosevka Slab - use Medium weight for better visibility (TTC files have family name "Iosevka Slab Medium")
  if [[ "$font_name" =~ "Iosevka".*"Slab" ]]; then
    local medium_family="${font_name} Medium"
    font_file=$(fc-list : family file style | grep -F "$medium_family" | grep -iE "style=(Medium|Semibold)" | head -1 | cut -d: -f1 | xargs)
    if [[ -n "$font_file" ]]; then
      echo "$font_file"
      return 0
    fi
  fi

  # Nimbus Mono PS - use Bold for better visibility (only has Regular and Bold)
  if [[ "$font_name" == "Nimbus Mono PS" ]]; then
    font_file=$(fc-list : family file style | grep -F "$font_name" | grep -iE "style=Bold$" | head -1 | cut -d: -f1 | xargs)
    if [[ -n "$font_file" ]]; then
      echo "$font_file"
      return 0
    fi
  fi

  # Try to get Regular style first (must be primary style, not secondary in TTC)
  # Handles numeric weight prefixes like "400 Regular" or plain "Regular"
  font_file=$(fc-list : family file style | grep -F "$font_name" | grep -iE "style=([0-9]+ )?(Regular|Normal|Book|Roman)(,|$)" | head -1 | cut -d: -f1 | xargs)

  # If no Regular variant, fall back to any variant (but skip Bold/Italic if possible)
  if [[ -z "$font_file" ]]; then
    font_file=$(fc-list : family file style | grep -F "$font_name" | grep -viE "style=(Bold|Italic|Light|Thin|Black|Heavy|Oblique|Slant)" | head -1 | cut -d: -f1 | xargs)
  fi

  # If still nothing, just take whatever is available
  if [[ -z "$font_file" ]]; then
    font_file=$(fc-list : family file | grep -F "$font_name" | head -1 | cut -d: -f1 | xargs)
  fi

  if [[ -z "$font_file" ]] || [[ ! -f "$font_file" ]]; then
    return 1
  fi

  echo "$font_file"
  return 0
}

# Get font style information for a font family
# Args: $1 - font family name
# Returns: Style name (e.g., "Regular", "Bold", etc.)
get_font_style() {
  local font_name="$1"

  fc-list : family file style | grep -F "$font_name" | grep -iE "style=(Regular|Normal|Book|Medium|Roman)" | head -1 | cut -d: -f3 | sed 's/style=//' | xargs || echo "Unknown"
}

# Get the preview text from external file
# Returns: Preview text on stdout
# Exit: 0 on success, 1 if file not found
get_preview_text() {
  if [[ ! -f "$PREVIEW_TEXT_FILE" ]]; then
    echo "Error: Preview text file not found: $PREVIEW_TEXT_FILE" >&2
    return 1
  fi

  cat "$PREVIEW_TEXT_FILE"
}

# Generate a preview image for a font with syntax highlighting
# Args: $1 - font family name
#       $2 - output PNG file path
# Returns: Nothing on stdout (errors to stderr)
# Exit: 0 on success, 1 on failure
generate_font_preview() {
  local font_name="$1"
  local output_file="$2"
  local font_file

  # Get font file path
  if ! font_file=$(get_font_file_path "$font_name"); then
    echo "Error: Font not found: $font_name" >&2
    return 1
  fi

  # Check required tools
  if ! command -v magick &>/dev/null; then
    echo "Error: ImageMagick not found" >&2
    return 1
  fi

  # Generate syntax-highlighted preview using ImageMagick only
  _generate_plain_preview "$font_file" "$output_file"

  # Verify the output file exists and has content
  if [[ ! -f "$output_file" ]] || [[ ! -s "$output_file" ]]; then
    echo "Error: Preview file is empty or not created" >&2
    return 1
  fi

  return 0
}

# Internal: Generate syntax-highlighted preview using ImageMagick only
_generate_plain_preview() {
  local font_file="$1"
  local output_file="$2"

  # Get the font style to show in preview
  local font_style=$(fc-list "$font_file" : style | cut -d: -f2 | sed 's/style=//' | xargs)
  [[ -z "$font_style" ]] && font_style="Regular"

  # Get the font family name
  local font_family=$(fc-list "$font_file" : family | cut -d: -f2 | xargs | head -1)

  # Create preview with consistent 35px line spacing and 50px section gaps
  # shellcheck disable=SC2016
  magick -size 1200x1600 xc:'#1e1e1e' \
    -font "$font_file" -pointsize 18 \
    `# Font family and style at top (25px spacing for header)` \
    -fill '#4ec9b0' -annotate +40+30 "$font_family" \
    -fill '#858585' -pointsize 14 -annotate +40+55 "Style: $font_style" \
    -pointsize 18 \
    `# Character section (35px spacing)` \
    -fill '#569cd6' -annotate +40+100 'Character Test & Differentiation:' \
    -fill '#d4d4d4' -annotate +40+135 'AaBbCc DdEeFf GgHhIi JjKkLl MmNnOo PpQqRr SsTtUu VvWwXx YyZz' \
    -fill '#d4d4d4' -annotate +40+170 '0O 1lI 5S 8B !|¦ .,;: <>«» {}[]() =-+*/% &@#$^~\|' \
    -fill '#d4d4d4' -annotate +40+205 'Ligatures: == != === !== <= >= => -> <-> ++ -- && ||' \
    `# Python section (50px gap, then 35px spacing)` \
    -fill '#569cd6' -annotate +40+255 'Python:' \
    -fill '#d4d4d4' -annotate +40+290 'from typing import Dict, List, Optional' \
    -fill '#d4d4d4' -annotate +40+325 '@functools.lru_cache(maxsize=128)' \
    -fill '#d4d4d4' -annotate +40+360 'def process(data: Dict[str, any]) -> Optional[List]:' \
    -fill '#d4d4d4' -annotate +80+395 'return [x**2 for x in data if x > 0]' \
    `# Go section (50px gap, then 35px spacing)` \
    -fill '#569cd6' -annotate +40+445 'Go:' \
    -fill '#d4d4d4' -annotate +40+480 'type Processor interface {' \
    -fill '#d4d4d4' -annotate +80+515 'Process(ctx context.Context) (Result, error)' \
    -fill '#d4d4d4' -annotate +40+550 '}' \
    `# Rust section (50px gap, then 35px spacing)` \
    -fill '#569cd6' -annotate +40+600 'Rust:' \
    -fill '#d4d4d4' -annotate +40+635 'use std::collections::HashMap;' \
    -fill '#d4d4d4' -annotate +40+705 'impl<T: Clone> Config<T> {' \
    -fill '#d4d4d4' -annotate +80+740 'pub fn get(&self, key: &str) -> Option<T> {' \
    -fill '#d4d4d4' -annotate +120+775 'self.data.get(key).cloned()' \
    -fill '#d4d4d4' -annotate +80+810 '}' \
    -fill '#d4d4d4' -annotate +40+845 '}' \
    `# Bash section (50px gap, then 35px spacing)` \
    -fill '#569cd6' -annotate +40+895 'Bash:' \
    -fill '#608b4e' -annotate +40+930 '#!/usr/bin/env bash' \
    -fill '#d4d4d4' -annotate +40+965 'declare -A config=([host]="localhost" [port]="8080")' \
    -fill '#d4d4d4' -annotate +40+1035 'for file in "${dir}"/**/*.log; do' \
    -fill '#d4d4d4' -annotate +80+1070 'result=$(awk -F"|" '\''{sum+=$3} END {print sum}'\'' "$file")' \
    -fill '#d4d4d4' -annotate +40+1105 'done' \
    -quality 100 \
    "$output_file"

  # shellcheck disable=SC2181
  if [[ $? -ne 0 ]]; then
    echo "Error: ImageMagick failed to generate preview" >&2
    return 1
  fi

  return 0
}

# Validate a preview image file
# Args: $1 - path to image file
# Returns: File type info on stdout
# Exit: 0 if valid PNG, 1 otherwise
validate_preview_image() {
  local image_file="$1"

  if [[ ! -f "$image_file" ]]; then
    echo "Error: File does not exist: $image_file" >&2
    return 1
  fi

  if [[ ! -s "$image_file" ]]; then
    echo "Error: File is empty: $image_file" >&2
    return 1
  fi

  # Check it's a valid PNG
  local file_type
  file_type=$(file "$image_file")

  if [[ ! "$file_type" =~ PNG ]]; then
    echo "Error: Not a PNG image: $file_type" >&2
    return 1
  fi

  echo "$file_type"
  return 0
}

# Get cached preview path for a font
# Args: $1 - font family name
# Returns: Path to cached preview file
get_cached_preview_path() {
  local font_name="$1"
  local safe_name

  # Convert font name to safe filename
  # shellcheck disable=SC2001
  safe_name=$(echo "$font_name" | sed 's/[^a-zA-Z0-9]/_/g')

  echo "$PREVIEW_CACHE_DIR/${safe_name}.png"
}

# Get or generate a preview (uses cache)
# Args: $1 - font family name
# Returns: Path to preview file on stdout
# Exit: 0 on success, 1 on failure
get_or_generate_preview() {
  local font_name="$1"
  local cache_file

  cache_file=$(get_cached_preview_path "$font_name")

  # Create cache directory if needed
  mkdir -p "$PREVIEW_CACHE_DIR"

  # Use cached version if it exists
  if [[ -f "$cache_file" ]]; then
    echo "$cache_file"
    return 0
  fi

  # Generate new preview
  if generate_font_preview "$font_name" "$cache_file"; then
    echo "$cache_file"
    return 0
  else
    return 1
  fi
}

# Display a preview image in the terminal
# Args: $1 - path to image file
# Exit: 0 on success, 1 if no display tool available
display_preview_image() {
  local image_file="$1"

  if ! validate_preview_image "$image_file" >/dev/null; then
    return 1
  fi

  if command -v chafa &>/dev/null; then
    chafa -f kitty "$image_file" 2>/dev/null
    return 0
  elif command -v viu &>/dev/null; then
    viu -w 120 "$image_file" 2>/dev/null
    return 0
  else
    echo "No image display tool found (install chafa or viu)" >&2
    return 1
  fi
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# Clear the preview cache
clear_preview_cache() {
  rm -rf "$PREVIEW_CACHE_DIR"
  mkdir -p "$PREVIEW_CACHE_DIR"
  echo "Preview cache cleared"
}

# Count available fonts
count_fonts() {
  list_fonts | wc -l | xargs
}

# ==============================================================================
# FONT INFO DISPLAY
# ==============================================================================

# Get font information from registry
# Args: $1 - font name
# Returns: JSON object with font info
get_font_info() {
  local font="$1"
  jq -r --arg font "$font" '.[$font] // {}' "$FONT_REGISTRY_FILE"
}

# Display font details (stats + info) - used by both 'font current' and preview
# Args: $1 - font name
#       $2 - format ("full" for font current, "compact" for preview)
display_font_details() {
  local font="$1"
  local format="${2:-full}"

  # Source storage.sh if needed (for preview script)
  if ! type -t get_font_stats &>/dev/null; then
    source "$FONT_APP_DIR/lib/storage.sh" 2>/dev/null || true
  fi

  if [[ "$format" == "full" ]]; then
    echo ""
    echo "Current Font: $font"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
  else
    echo "━━━ $font ━━━"
  fi

  # Get stats from history
  if type -t get_font_stats &>/dev/null; then
    local stats
    stats=$(get_font_stats "$font" 2>/dev/null)

    if [[ -n "$stats" ]] && [[ "$stats" != "null" ]]; then
      local score=$(echo "$stats" | jq -r '.score // 0')
      local likes=$(echo "$stats" | jq -r '.likes // 0')
      local dislikes=$(echo "$stats" | jq -r '.dislikes // 0')
      local notes=$(echo "$stats" | jq -r '.notes // 0')
      local applies=$(echo "$stats" | jq -r '.applies // 0')
      local platforms=$(echo "$stats" | jq -r '.platforms | join(", ") // "none"')

      # Calculate usage time
      if type -t calculate_usage_time &>/dev/null; then
        local usage_times
        usage_times=$(calculate_usage_time "$font")
        local usage_seconds=$(echo "$usage_times" | jq -r --arg font "$font" '.[$font] // 0')
        local usage_time="not used"
        if [[ "$usage_seconds" -gt 0 ]] && type -t format_duration &>/dev/null; then
          usage_time=$(format_duration "$usage_seconds")
        fi
      fi

      if [[ "$format" == "full" ]]; then
        echo "Stats:"
        printf "  Score: %+d (%d likes, %d dislikes)\n" "$score" "$likes" "$dislikes"
        [[ -n "$usage_time" ]] && printf "  Usage time: %s\n" "$usage_time"
        printf "  Notes: %d\n" "$notes"
        printf "  Times applied: %d\n" "$applies"
        printf "  Platforms: %s\n" "$platforms"
        local machines=$(echo "$stats" | jq -r '.machines | join(", ") // "unknown"')
        printf "  Machines: %s\n" "$machines"

        # Show terminal context from last apply
        if type -t get_last_terminal_context &>/dev/null; then
          local ctx
          ctx=$(get_last_terminal_context "$font" 2>/dev/null)
          if [[ -n "$ctx" ]] && [[ "$ctx" != "{}" ]] && [[ "$ctx" != "null" ]]; then
            local terminal=$(echo "$ctx" | jq -r '.terminal // "unknown"')
            local in_tmux=$(echo "$ctx" | jq -r '.in_tmux // "unknown"')
            local cols=$(echo "$ctx" | jq -r '.cols // "unknown"')
            local rows=$(echo "$ctx" | jq -r '.rows // "unknown"')
            local resolution=$(echo "$ctx" | jq -r '.resolution // "unknown"')
            local font_size=$(echo "$ctx" | jq -r '.font_size // "unknown"')

            echo ""
            echo "Last Session:"
            printf "  Terminal: %s\n" "$terminal"
            [[ "$cols" != "null" && "$cols" != "unknown" ]] && printf "  Size: %sx%s (cols x rows)\n" "$cols" "$rows"
            [[ "$font_size" != "null" && "$font_size" != "unknown" ]] && printf "  Font size: %s\n" "$font_size"
            [[ "$resolution" != "null" && "$resolution" != "unknown" ]] && printf "  Resolution: %s\n" "$resolution"
            [[ "$in_tmux" != "null" ]] && printf "  In tmux: %s\n" "$in_tmux"
          fi
        fi

        # Show history for this font (tells the story)
        if type -t get_history &>/dev/null; then
          local history_count
          history_count=$(get_history | jq --arg font "$font" '[.[] | select(.font == $font)] | length')
          if [[ "$history_count" -gt 0 ]]; then
            echo ""
            echo "History:"
            get_history | jq -r --arg font "$font" '
              map(select(.font == $font)) |
              sort_by(.ts) |
              .[] |
              .action as $act |
              .ts[0:10] as $date |
              .message as $msg |
              if $act == "apply" then
                "  \($date)  applied"
              elif $act == "like" then
                if $msg then "  \($date)  liked: \($msg)" else "  \($date)  liked" end
              elif $act == "dislike" then
                if $msg then "  \($date)  disliked: \($msg)" else "  \($date)  disliked" end
              elif $act == "note" then
                "  \($date)  note: \($msg)"
              elif $act == "reject" then
                "  \($date)  rejected: \($msg)"
              elif $act == "unreject" then
                "  \($date)  unrejected"
              else
                "  \($date)  \($act)"
              end
            ' 2>/dev/null
          fi
        fi
      else
        # Compact format for preview
        printf "Score: %+d (%d↑ %d↓)" "$score" "$likes" "$dislikes"
        [[ -n "$usage_time" ]] && printf " | Used: %s" "$usage_time"
        echo ""
      fi
    fi
  fi

  # Get font description/info
  local font_info
  font_info=$(get_font_info "$font")

  if [[ -n "$font_info" ]] && [[ "$font_info" != "{}" ]]; then
    local description=$(echo "$font_info" | jq -r '.description // empty')
    local known_for=$(echo "$font_info" | jq -r '.known_for // empty')
    local creator=$(echo "$font_info" | jq -r '.creator // empty')
    local year=$(echo "$font_info" | jq -r '.year // empty')
    local url=$(echo "$font_info" | jq -r '.url // empty')

    if [[ -n "$description" ]]; then
      if [[ "$format" == "full" ]]; then
        echo ""
        echo "About:"
        echo "  $description"
        [[ -n "$known_for" ]] && echo "  Known for: $known_for"
        [[ -n "$creator" ]] && echo "  Creator: $creator"
        [[ -n "$year" ]] && echo "  Year: $year"
        [[ -n "$url" ]] && echo "  URL: $url"
      else
        # Compact format for preview
        echo "$description"
        [[ -n "$known_for" ]] && echo "Known for: $known_for"
        [[ -n "$creator" ]] && echo "Creator: $creator ($year)"
      fi
    fi
  fi

  if [[ "$format" == "full" ]]; then
    echo ""
  else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  fi
}

# ==============================================================================
# PLATFORM DETECTION
# ==============================================================================

detect_platform() {
  if [[ -n "${PLATFORM:-}" ]]; then
    echo "$PLATFORM"
    return
  fi

  if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macos"
  elif [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
    echo "wsl"
  elif [[ -f /etc/arch-release ]]; then
    echo "archlinux"
  else
    echo "linux"
  fi
}

# Arch-specific font functions moved to lib/terminals/arch.sh

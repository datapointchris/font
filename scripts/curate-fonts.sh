#!/usr/bin/env bash
# Curate fonts: extract, patch, rename, and package for GitHub Release
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR=$(mktemp -d /tmp/font-curate-XXXX)
FONTS_SRC="$HOME/.local/share/fonts"
STAGING="$WORK_DIR/staging"
OUTPUT="$SCRIPT_DIR/../fonts.tar.xz"

echo "Working directory: $WORK_DIR"
mkdir -p "$STAGING"

# ── Step 1: Copy the 11 curated font families ──────────────────────────

echo ""
echo "Step 1: Copying curated fonts..."

# The 11 families (by filename prefix) — excludes rejected CaskaydiaCove and JetBrainsMonoNL
families=(
  "ComicMonoNF"
  "ComicShannsMonoNerdFont"
  "FiraCodeNerdFont"
  "HackNerdFont"
  "IosevkaNerdFont"
  "JetBrainsMonoNerdFont"
  "MesloLGMNerdFont"
  "MonaspiceNeNerdFont"
  "RobotoMonoNerdFont"
  "SeriousShannsNerdFontMono"
)

for family in "${families[@]}"; do
  files=("$FONTS_SRC"/${family}-*.ttf "$FONTS_SRC"/${family}-*.otf "$FONTS_SRC"/${family}Mono-*.ttf "$FONTS_SRC"/${family}Mono-*.otf)
  count=0
  for f in "${files[@]}"; do
    if [[ -f "$f" ]]; then
      cp "$f" "$STAGING/"
      count=$((count + 1))
    fi
  done
  echo "  $family: $count files"
done

# ── Step 2: Extract Iosevka Term Slab from SuperTTC ────────────────────

echo ""
echo "Step 2: Extracting Iosevka Term Slab from SuperTTC..."

IOSEVKA_TTC="$FONTS_SRC/SGr-IosevkaTermSlab.ttc"
IOSEVKA_EXTRACT="$WORK_DIR/iosevka-extract"
mkdir -p "$IOSEVKA_EXTRACT"

uvx --from fonttools python3 -c "
from fontTools.ttLib import TTFont
import os

ttc_path = '$IOSEVKA_TTC'
out_dir = '$IOSEVKA_EXTRACT'

# Load one font at a time to avoid OOM on 482MB SuperTTC
extracted = 0
i = 0
while True:
    try:
        font = TTFont(ttc_path, fontNumber=i, lazy=True)
    except Exception:
        break

    name_table = font['name']
    family = name_table.getDebugName(1) or ''
    subfamily = name_table.getDebugName(2) or ''
    weight = font['OS/2'].usWeightClass

    # Match exactly 'Iosevka Term Slab' — not Extended, not Medium, etc.
    if family.strip() == 'Iosevka Term Slab':
        if weight == 400 and 'Italic' not in subfamily and 'Oblique' not in subfamily:
            out = os.path.join(out_dir, 'IosevkaTermSlab-Regular.ttf')
            font.save(out)
            print(f'  Extracted: {family} {subfamily} (weight {weight})')
            extracted += 1
        elif weight == 700 and 'Italic' not in subfamily and 'Oblique' not in subfamily:
            out = os.path.join(out_dir, 'IosevkaTermSlab-Bold.ttf')
            font.save(out)
            print(f'  Extracted: {family} {subfamily} (weight {weight})')
            extracted += 1

    font.close()

    if extracted >= 2:
        break
    i += 1

print(f'  Scanned {i+1} fonts, extracted {extracted}')
" 2>&1

# ── Step 3: Patch Iosevka Term Slab with Nerd Font glyphs ─────────────

echo ""
echo "Step 3: Patching Iosevka Term Slab with Nerd Font glyphs..."

IOSEVKA_PATCHED="$WORK_DIR/iosevka-patched"
mkdir -p "$IOSEVKA_PATCHED"

# Patch one file at a time (patcher auto-processes everything in /in/)
for ttf in "$IOSEVKA_EXTRACT"/*.ttf; do
  echo "  Patching $(basename "$ttf")..."
  SINGLE_IN="$WORK_DIR/patch-in"
  rm -rf "$SINGLE_IN" && mkdir -p "$SINGLE_IN"
  cp "$ttf" "$SINGLE_IN/"
  docker run --rm \
    -v "$SINGLE_IN":/in \
    -v "$IOSEVKA_PATCHED":/out \
    nerdfonts/patcher \
    --complete --no-progressbars
done

echo "  Patched files:"
ls -lh "$IOSEVKA_PATCHED"/ 2>/dev/null

# Copy patched files to staging
cp "$IOSEVKA_PATCHED"/*.ttf "$STAGING/" 2>/dev/null || true

# ── Step 4: Rename all fonts to have spaces ────────────────────────────

echo ""
echo "Step 4: Renaming all fonts to use spaces in family names..."

uvx --from fonttools python3 -c "
import os, glob, re

# Rename mapping: old family name -> new family name
RENAMES = {
    'CaskaydiaCove Nerd Font': 'Caskaydia Cove Nerd Font',
    'CaskaydiaCove Nerd Font Mono': 'Caskaydia Cove Nerd Font Mono',
    'ComicMonoNF': 'Comic Mono Nerd Font',
    'ComicShannsMono Nerd Font': 'Comic Shanns Mono Nerd Font',
    'ComicShannsMono Nerd Font Mono': 'Comic Shanns Mono Nerd Font Mono',
    'FiraCode Nerd Font': 'Fira Code Nerd Font',
    'FiraCode Nerd Font Mono': 'Fira Code Nerd Font Mono',
    'JetBrainsMono Nerd Font': 'JetBrains Mono Nerd Font',
    'JetBrainsMono Nerd Font Mono': 'JetBrains Mono Nerd Font Mono',
    'MesloLGM Nerd Font': 'Meslo LGM Nerd Font',
    'MesloLGM Nerd Font Mono': 'Meslo LGM Nerd Font Mono',
    'MonaspiceNe Nerd Font': 'Monaspice Ne Nerd Font',
    'MonaspiceNe Nerd Font Mono': 'Monaspice Ne Nerd Font Mono',
    'RobotoMono Nerd Font': 'Roboto Mono Nerd Font',
    'RobotoMono Nerd Font Mono': 'Roboto Mono Nerd Font Mono',
    'SeriousShanns Nerd Font Mono': 'Serious Shanns Nerd Font Mono',
    # Abbreviated NF/NFM variants (Nerd Fonts v3 uses short names in some files)
    'Iosevka NF': 'Iosevka Nerd Font',
    'Iosevka NFM': 'Iosevka Nerd Font Mono',
    'JetBrainsMono NF': 'JetBrains Mono Nerd Font',
    'JetBrainsMono NFM': 'JetBrains Mono Nerd Font Mono',
    'MonaspiceNe NF': 'Monaspice Ne Nerd Font',
    'MonaspiceNe NFM': 'Monaspice Ne Nerd Font Mono',
    'CaskaydiaCove NF': 'Caskaydia Cove Nerd Font',
    'CaskaydiaCove NFM': 'Caskaydia Cove Nerd Font Mono',
    'ComicShannsMono NF': 'Comic Shanns Mono Nerd Font',
    'ComicShannsMono NFM': 'Comic Shanns Mono Nerd Font Mono',
    'FiraCode NF': 'Fira Code Nerd Font',
    'FiraCode NFM': 'Fira Code Nerd Font Mono',
    'Hack NF': 'Hack Nerd Font',
    'Hack NFM': 'Hack Nerd Font Mono',
    'MesloLGM NF': 'Meslo LGM Nerd Font',
    'MesloLGM NFM': 'Meslo LGM Nerd Font Mono',
    'RobotoMono NF': 'Roboto Mono Nerd Font',
    'RobotoMono NFM': 'Roboto Mono Nerd Font Mono',
}

def rename_font(filepath):
    from fontTools.ttLib import TTFont

    tt = TTFont(filepath)
    name_table = tt['name']
    changed = False

    current_family = name_table.getDebugName(1) or ''

    # Check exact match first
    new_family = RENAMES.get(current_family)

    # For Iosevka Term Slab from patcher (may have various formats)
    if not new_family and 'IosevkaTermSlab' in current_family:
        new_family = current_family.replace('IosevkaTermSlab', 'Iosevka Term Slab')

    # Prefix match for abbreviated names with weight suffixes
    # e.g., "Iosevka NF Heavy" -> "Iosevka Nerd Font Heavy"
    if not new_family:
        for old_prefix, new_prefix in RENAMES.items():
            if current_family.startswith(old_prefix + ' '):
                suffix = current_family[len(old_prefix):]
                new_family = new_prefix + suffix
                break

    if not new_family:
        tt.close()
        return False, current_family

    # Build the PostScript-safe version (no spaces)
    new_ps_family = new_family.replace(' ', '')

    for record in name_table.names:
        try:
            old_val = record.toUnicode()
        except UnicodeDecodeError:
            continue

        new_val = old_val

        if record.nameID == 1:  # Family name
            new_val = new_family
        elif record.nameID == 4:  # Full name
            new_val = old_val.replace(current_family, new_family)
        elif record.nameID == 6:  # PostScript name (no spaces allowed)
            # Replace the old family (no spaces) with new (no spaces)
            old_ps = current_family.replace(' ', '')
            new_val = old_val.replace(old_ps, new_ps_family)
        elif record.nameID == 16:  # Typographic Family
            new_val = old_val.replace(current_family, new_family)
        elif record.nameID == 17:  # Typographic Subfamily
            pass  # Leave subfamily as-is

        if new_val != old_val:
            record.string = new_val
            changed = True

    if changed:
        tt.save(filepath)
    tt.close()
    return changed, new_family

staging = '$STAGING'
fonts = glob.glob(os.path.join(staging, '*.ttf')) + glob.glob(os.path.join(staging, '*.otf'))

renamed_count = 0
for f in sorted(fonts):
    changed, name = rename_font(f)
    if changed:
        print(f'  Renamed: {os.path.basename(f)} -> \"{name}\"')
        renamed_count += 1

print(f'  Total renamed: {renamed_count}/{len(fonts)} files')
" 2>&1

# ── Step 5: Verify ────────────────────────────────────────────────────

echo ""
echo "Step 5: Verifying font family names..."

uvx --from fonttools python3 -c "
import os, glob
from fontTools.ttLib import TTFont

staging = '$STAGING'
fonts = glob.glob(os.path.join(staging, '*.ttf')) + glob.glob(os.path.join(staging, '*.otf'))

families = set()
for f in sorted(fonts):
    tt = TTFont(f)
    family = tt['name'].getDebugName(1) or 'UNKNOWN'
    families.add(family)
    tt.close()

for fam in sorted(families):
    print(f'  {fam}')
print(f'\n  Total: {len(families)} font families, {len(fonts)} files')
" 2>&1

# ── Step 6: Package ───────────────────────────────────────────────────

echo ""
echo "Step 6: Creating archive..."

cd "$STAGING"
tar cf - *.ttf *.otf 2>/dev/null | xz -9 > "$OUTPUT"

size=$(du -h "$OUTPUT" | cut -f1)
echo "  Archive: $OUTPUT ($size)"

# ── Cleanup ───────────────────────────────────────────────────────────

echo ""
echo "Done! Working directory preserved at: $WORK_DIR"
echo "Archive ready at: $OUTPUT"

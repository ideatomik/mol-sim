#!/bin/bash
# deploy_wiki.sh - Prepares Zymulador wiki pages for GitHub Wiki deployment
# 
# Usage: ./deploy_wiki.sh
# Then follow the instructions at the end to push to your GitHub wiki repo

echo "🔧 Preparing Zymulador Wiki pages for GitHub..."

# Create output directory
WIKI_OUTPUT="wiki_pages"
rm -rf "$WIKI_OUTPUT"
mkdir -p "$WIKI_OUTPUT"

# Source wiki file
SOURCE_WIKI="docs/WIKI.md"

if [ ! -f "$SOURCE_WIKI" ]; then
    echo "❌ Error: $SOURCE_WIKI not found!"
    exit 1
fi

echo "📄 Reading from $SOURCE_WIKI"

# Function to extract section between two ## headers
extract_section() {
    local section_title="$1"
    local output_file="$2"
    local display_title="$3"
    
    echo "   Creating $output_file..."
    
    # Write title header
    echo "# $display_title" > "$WIKI_OUTPUT/$output_file"
    echo "" >> "$WIKI_OUTPUT/$output_file"
    
    # Extract from the section header to the next ## header
    awk -v title="## $section_title" '
        BEGIN { capture=0 }
        $0 == title { capture=1; next }
        capture && /^## / { capture=0 }
        capture { print }
    ' "$SOURCE_WIKI" >> "$WIKI_OUTPUT/$output_file"
}

# Create Home.md (Overview + Feature Status Matrix)
cat > "$WIKI_OUTPUT/Home.md" << 'EOF'
# Zymulador Wiki — Comprehensive Architecture Guide

**Last Updated**: Based on codebase v85 (August 2026)

**Companion Documents**: This wiki summarizes *implemented* architecture. For full design rationale, planned features, and biological model, see the links below.

---

## ⚠️ Implemented vs. Planned Features

**This wiki distinguishes between what is built now vs. what is designed but not yet implemented.** Many features documented in `/docs` are *planned* but not yet coded.

---

## Quick Navigation

- [[Project Structure & File Organization]]
- [[Core Architecture & Manager Hierarchy]]
- [[Script Reference]]
- [[Data Flow & Relationships]]
- [[Flowcharts & Diagrams]]
- [[Key Parameters & Configuration]]
- [[Signal Communication Map]]
- [[Planned Features Roadmap]]

---

EOF

# Append Overview section
extract_section "Overview" "Home.md.tmp" "Overview"
cat "$WIKI_OUTPUT/Home.md.tmp" >> "$WIKI_OUTPUT/Home.md"
rm -f "$WIKI_OUTPUT/Home.md.tmp"

# Append Feature Status Matrix
extract_section "Feature Status Matrix" "Home.md.tmp" "Feature Status Matrix"
cat "$WIKI_OUTPUT/Home.md.tmp" >> "$WIKI_OUTPUT/Home.md"
rm -f "$WIKI_OUTPUT/Home.md.tmp"

# Add footer with navigation
cat >> "$WIKI_OUTPUT/Home.md" << 'EOF'

---

## About This Wiki

This wiki documents the **implemented** features of Zymulador as of August 2026. For detailed design documents, roadmap, and planned features, visit the [`docs/`](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/tree/main/docs) folder in the main repository.

### Key Design Documents
- [DESIGN.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/architecture/DESIGN.md) — Stable philosophy and biological model
- [STATUS.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/architecture/STATUS.md) — Current implementation state and roadmap
- [COMPLEXITY_MODEL.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/architecture/COMPLEXITY_MODEL.md) — Complexity toggle system
- [TODO.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/architecture/TODO.md) — Working list of bugs and features

---

*Generated automatically from docs/WIKI.md*
EOF

# Create individual pages
extract_section "Project Structure" "Project-Structure.md" "Project Structure & File Organization"
extract_section "Core Architecture" "Core-Architecture.md" "Core Architecture & Manager Hierarchy"
extract_section "Script Reference" "Script-Reference.md" "Script Reference"
extract_section "Data Flow & Relationships" "Data-Flow.md" "Data Flow & Relationships"
extract_section "Flowcharts" "Flowcharts.md" "Flowcharts & Diagrams"
extract_section "Key Parameters & Configuration" "Parameters.md" "Key Parameters & Configuration"
extract_section "Signal Communication" "Signal-Communication.md" "Signal Communication Map"

# Create Planned Features page
cat > "$WIKI_OUTPUT/Planned-Features.md" << 'EOF'
# Planned Features Roadmap

This page lists features that are **designed but not yet implemented**. See individual design documents in the `docs/` folder for detailed specifications.

## Features Not Yet Implemented

| Feature | Complexity Tier | Design Doc | Description |
|---------|-----------------|------------|-------------|
| Trombone loop model | High | [TromboneLoopDesign.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/enzymes/TromboneLoopDesign.md) | Lagging polymerase coupled to replisome via τ body |
| Full replisome (clamp loader, β-clamps) | High | [COMPLEXITY_MODEL.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/architecture/COMPLEXITY_MODEL.md) | Clamp visuals exist but not as separate toggles |
| Telomerase enzyme visual | Eukaryotic-only | [TelomeraseDesign.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/enzymes/TelomeraseDesign.md) | Extends template strand, requires dynamic sequence growth |
| SSB/shelterin | Stage 2 elongation | [COMPLEXITY_MODEL.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/architecture/COMPLEXITY_MODEL.md) | Coats ssDNA behind helicase |
| Tus-Ter termination | Circular-only | [TusTerDesign.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/enzymes/TusTerDesign.md) | Fork trap for circular chromosomes |
| Topoisomerase | Advanced | [Topoisomerase.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/enzymes/Topoisomerase.md) | Relieves torsional strain ahead of fork |
| Bidirectional replication | Circular | [TusTerDesign.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/enzymes/TusTerDesign.md) | Two replisomes from single origin |
| Transcription phase | — | [DESIGN.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/architecture/DESIGN.md) | Post-replication central dogma phase |
| Translation phase | — | [DESIGN.md](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/architecture/DESIGN.md) | Final central dogma phase |

## Implementation Priority

Based on [`docs/architecture/STATUS.md`](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/docs/architecture/STATUS.md):

1. **High Priority**: Trombone loop model, full replisome components
2. **Medium Priority**: Telomerase enzyme, SSB/shelterin proteins
3. **Lower Priority**: Tus-Ter termination, topoisomerase, bidirectional replication
4. **Future Scope**: Transcription and Translation phases

---

*For detailed design specifications, visit the [`docs/`](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/tree/main/docs) folder in the main repository.*
EOF

# Create _Sidebar.md for navigation
cat > "$WIKI_OUTPUT/_Sidebar.md" << 'EOF'
## 📚 Zymulador Wiki

### Getting Started
- [[Home|Home]]

### Architecture
- [[Project Structure|Project-Structure]]
- [[Core Architecture|Core-Architecture]]
- [[Script Reference|Script-Reference]]

### Technical Details
- [[Data Flow|Data-Flow]]
- [[Flowcharts|Flowcharts]]
- [[Parameters|Parameters]]
- [[Signal Communication|Signal-Communication]]

### Roadmap
- [[Planned Features|Planned-Features]]

### External Links
- [Main Repository](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME)
- [Design Documents](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/tree/main/docs)
- [README](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/blob/main/README.md)
EOF

# Create _Footer.md
cat > "$WIKI_OUTPUT/_Footer.md" << 'EOF'
---
*Zymulador Wiki | Last updated: August 2026 | [Report issues](https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/issues)*
EOF

echo ""
echo "✅ Wiki pages created successfully in '$WIKI_OUTPUT/' directory!"
echo ""
echo "📁 Generated files:"
ls -la "$WIKI_OUTPUT/"
echo ""
echo "==================================================================="
echo "🚀 DEPLOYMENT INSTRUCTIONS"
echo "==================================================================="
echo ""
echo "1. Replace YOUR_USERNAME and YOUR_REPO_NAME in the generated files:"
echo "   cd $WIKI_OUTPUT"
echo "   sed -i 's/YOUR_USERNAME/your-github-username/g' *.md"
echo "   sed -i 's/YOUR_REPO_NAME/your-repo-name/g' *.md"
echo ""
echo "2. Clone your GitHub wiki repository:"
echo "   git clone https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.wiki.git"
echo ""
echo "3. Copy all files to the wiki repo:"
echo "   cp $WIKI_OUTPUT/*.md YOUR_REPO_NAME.wiki/"
echo ""
echo "4. Commit and push:"
echo "   cd YOUR_REPO_NAME.wiki"
echo "   git add ."
echo "   git commit -m 'Add comprehensive Zymulador wiki'"
echo "   git push origin master"
echo ""
echo "5. Visit your wiki at: https://github.com/YOUR_USERNAME/YOUR_REPO_NAME/wiki"
echo ""
echo "==================================================================="
echo "📝 Note: GitHub Wiki uses the 'master' branch by default."
echo "   Mermaid diagrams are supported natively in GitHub Wiki."
echo "==================================================================="

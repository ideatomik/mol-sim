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

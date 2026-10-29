---
name: Trails
colors:
  surface: '#fdf9f0'
  surface-dim: '#dddad1'
  surface-bright: '#fdf9f0'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f7f3ea'
  surface-container: '#f1eee5'
  surface-container-high: '#ece8df'
  surface-container-highest: '#e6e2d9'
  on-surface: '#1c1c16'
  on-surface-variant: '#414846'
  inverse-surface: '#31302b'
  inverse-on-surface: '#f4f0e7'
  outline: '#717975'
  outline-variant: '#c0c8c4'
  surface-tint: '#40665b'
  primary: '#002820'
  on-primary: '#ffffff'
  primary-container: '#173e35'
  on-primary-container: '#81a99d'
  inverse-primary: '#a6cfc2'
  secondary: '#725c20'
  on-secondary: '#ffffff'
  secondary-container: '#ffdf96'
  on-secondary-container: '#786226'
  tertiary: '#450f00'
  on-tertiary: '#ffffff'
  tertiary-container: '#65210a'
  on-tertiary-container: '#e98768'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#c2ebde'
  primary-fixed-dim: '#a6cfc2'
  on-primary-fixed: '#00201a'
  on-primary-fixed-variant: '#274e44'
  secondary-fixed: '#ffdf96'
  secondary-fixed-dim: '#e1c37d'
  on-secondary-fixed: '#251a00'
  on-secondary-fixed-variant: '#584409'
  tertiary-fixed: '#ffdbd0'
  tertiary-fixed-dim: '#ffb59e'
  on-tertiary-fixed: '#3a0b00'
  on-tertiary-fixed-variant: '#793018'
  background: '#fdf9f0'
  on-background: '#1c1c16'
  surface-variant: '#e6e2d9'
typography:
  display-lg:
    fontFamily: Newsreader
    fontSize: 40px
    fontWeight: '400'
    lineHeight: 48px
    letterSpacing: -0.02em
  display-lg-mobile:
    fontFamily: Newsreader
    fontSize: 32px
    fontWeight: '400'
    lineHeight: 40px
    letterSpacing: -0.015em
  headline-lg:
    fontFamily: Newsreader
    fontSize: 28px
    fontWeight: '400'
    lineHeight: 36px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Newsreader
    fontSize: 22px
    fontWeight: '400'
    lineHeight: 30px
  headline-sm:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  label-spatial:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.06em
  label-metric:
    fontFamily: JetBrains Mono
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.02em
  label-ui:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 18px
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  gutter: 1rem
  margin: 1.25rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2.25rem
---

## Brand & Style
This design system expresses a refined indoor spatial exploration journal built natively for iOS. The aesthetic bridges architectural precision and contemplative curation, evoking the tactile luxury of an exhibition monograph paired with the technical authority of an interior survey instrument.

The design movement synthesizes **Modern Architectural Minimalism** with **Apple-native Tactility**:
- Rich, physical materials translated into digital space: unpolished limestone, oxidized brass markers, botanical deep forest chrome, and earthenware terracotta paths.
- RoomPlan and LiDAR spatial representations favor precise hairline wireframes and volumetric floor plans over synthetic gamified overlays.
- Tone is calm, observational, and elevated—devoid of commercial noise, streaks, or aggressive telemetry.

## Colors
The palette grounds spatial computing within organic, mineral materials. High contrast ensures readability when looking between handheld screens and dim gallery or atrium lighting.

### Color Roles
- **Canvas / Limestone (`#F5F1E8`)**: Base background simulating raw paperboard and natural stone.
- **Chrome & Primary Text / Forest Green (`#173E35`)**: Structural anchors, prominent navigation chrome, primary buttons, and deep brand presence.
- **Active Journey / Terracotta (`#C66B4E`)**: Active trail vector, current heading vectors, dynamic waypoints, and focused states.
- **Spatial Waypoints / Muted Brass (`#B59A58`)**: Moment pins, architectural milestones, and curatorial points of interest.
- **Reading Ink / Deep Ink (`#202923`)**: High-legibility editorial headings and primary informational text.
- **Elevated Canvas / Ivory (`#FAF8F5`)**: Floating surface panels, bottom sheets, and elevated overlays.
- **Base Surfaces / Pure White (`#FFFFFF`)**: Spatial detail cards, interactive controls, and modal dialogs.
- **Volumetric Trace (`rgba(23, 62, 53, 0.18)`)**: RoomPlan mesh surfaces, footprint bounds, and zone boundaries.
- **Inactive Vector (`rgba(156, 154, 142, 0.40)`)**: Unselected floors, background paths, and dormant structural vectors.

## Typography
The type hierarchy balances three distinct functional voices:
1. **Curatorial Editorial (`Newsreader`)**: Expressive, historical, and intellectual. Used for space titles, exhibition essays, wing names, and meditative field annotations.
2. **System Interface (`Inter`)**: Direct, neutral, and ergonomic. Serves dynamic bottom sheet listings, navigation commands, search fields, and general UI labels.
3. **Survey & Coordinates (`JetBrains Mono`)**: Strict, tabular, and instrumental. Reserved for floor levels (e.g., `LVL 02`), spatial offsets (`+14.2M`), RoomPlan volumetric dimensions, step cadences, and coordinate timestamps. All coordinate values must use tabular figures.

## Layout & Spacing
Built for standard handheld iOS interactions with full consideration of dynamic safe areas and one-handed reach zones.

- **Grid Model**: A flexible 4-column layout on standard iOS devices, expanding to 8 columns on iPad mini/split-view.
- **Canvas Margins**: Set to `1.25rem` (20px) to balance edge breathing room with maximum viewport map area.
- **Spatial HUD Overlay**: Camera and 3D RoomPlan viewports consume 100% of the canvas. Interactive controls, cards, and floating pills hug native iOS safe areas with minimum bottom clearance of `space-lg`.
- **Bottom Sheets**: Primary content interaction happens via draggable sheets snapping at 18%, 45%, and 88% screen height thresholds.

## Elevation & Depth
Depth is produced through ambient physical diffusion and native frosted optical transmission, avoiding artificial stark drops.

- **Level 0 (Map / Camera Bed)**: The underlying LiDAR point cloud, RoomPlan mesh, or vector floor plan rendered on `#F5F1E8`.
- **Level 1 (Inlaid Geometry)**: Active paths (`#C66B4E`) and inactive paths (`rgba(156, 154, 142, 0.40)`) drawn planar to the environment.
- **Level 2 (Floating Floating Controls & Indicators)**: Frosted glass pills using native backdrop blur (`blur(20px)`), with an ivory tint (`rgba(250, 248, 245, 0.85)`) and a delicate top stroke (`rgba(255, 255, 255, 0.60)`). Soft ambient shadow: `0 8px 24px rgba(32, 41, 35, 0.08)`.
- **Level 3 (Tactile Bottom Sheets & Modals)**: Opaque surfaces in `#FAF8F5` or pure `#FFFFFF` with a directional lift shadow: `0 -4px 32px rgba(23, 62, 53, 0.06)`, framed by a subtle 0.5px hairline outline in `rgba(23, 62, 53, 0.08)`.

## Shapes
Forms prioritize oversized, humanistic corner curves characteristic of modern iOS craftsmanship:
- **Pill Geometry (`rounded-full`)**: Floating HUD actions, floor-level selectors, filter tags, and primary call-to-action buttons.
- **Oversized Curves (`2rem` - `2.5rem`)**: Tactile bottom sheets, primary journey detail cards, and contextual alert dialogs.
- **Secondary Shells (`1rem`)**: Embedded inspection cards, coordinate badges, and spatial sensor diagnostics.

## Components

### Buttons
- **Primary CTA**: Forest Green (`#173E35`) fill, pure white text (`#FFFFFF`), full pill radius (`rounded-full`), height of 52px. Active state applies a subtle scale reduction (0.97) and tone darkening.
- **Secondary Action**: Ivory (`#FAF8F5`) fill with a 1px border of `rgba(23, 62, 53, 0.12)`. Forest Green text.
- **Spatial Floating Action**: Pill button with `rgba(250, 248, 245, 0.90)` frosted blur, containing a `Newsreader` title and a `JetBrains Mono` distance metric.

### Segmented Floor Selector
- Floating pill dock housing individual floor levels (`LVL 01`, `LVL 02`).
- Selected floor state: Solid Forest Green (`#173E35`) capsule with pure white monospace type.
- Unselected floor: Translucent text in `#202923` with interactive press states.

### Spatial Waypoint Pins (Moment Pins)
- Circular Muted Brass (`#B59A58`) core (8px) bounded by an outer concentric halo (24px) rendered with 15% opacity.
- Paired with an anchored pill flag displaying the place name in `Newsreader` and survey metric in `JetBrains Mono`.

### Active Trail Vectors
- Continuous vector stroke in Terracotta (`#C66B4E`) with a 3px core thickness and an anchor node emitting a soft glowing radius (`rgba(198, 107, 78, 0.25)`).
- Intersecting floor-plan transitions render as dashed vectors that soften into `rgba(156, 154, 142, 0.40)`.

### RoomPlan Spatial Cards
- White (`#FFFFFF`) surface with `rounded-3xl` corner radii.
- Clean architectural hairline divider (`rgba(23, 62, 53, 0.08)`).
- Headers set in `Newsreader` Display Medium, metadata tags set in `JetBrains Mono` label badges, and narrative body copy set in `Inter`.
- No gamified progress bars; status is rendered via minimal, discrete vector tick marks.

### Bottom Sheet Drawer
- Pull handle: 36px wide by 4px tall capsule in `rgba(32, 41, 35, 0.20)`.
- Container uses `#FAF8F5` with `rounded-t-[32px]` clipping.
- Contains curatorial journey narrative lines, elevation profiles, and RoomPlan spatial zone boundaries.
# ``LogrUI``

SwiftUI views for browsing, filtering, exporting and analysing LogR logs.

## Overview

Inject a service once at the app root with `.logRService(_:)`, then read it anywhere through the
`\.logService` environment value. Without an injected service the environment falls back to a
no-op logger, so views render an empty state instead of crashing. ``LogViewer`` has no navigation
container of its own: host it inside a `NavigationStack`.

``MockLogR`` ships with generated sample data for previews and UI tests.

## Topics

### Setup

- ``SwiftUICore/View/logRService(_:)``
- ``SwiftUICore/EnvironmentValues/logService``
- ``LogRServiceModifier``

### Views

- ``LogViewer``
- ``LogViewer/Functionalities``
- ``LogStatisticsView``
- ``CompactLogStatisticsView``
- ``AIAnalysisView``
- ``PrivacyWarningsView``
- ``IssueSummaryView``

### Viewer preferences

- ``LogFilterPreferences``
- ``LogTimeGrouping``
- ``LogTimeGroup``

### Mocking

- ``MockLogR``
- ``GenerationConfig``
- ``GenerationMode``

### Presentation

- ``Logr/LogLevel/tint``
- ``Logr/LogSeverity/tint``
- ``Logr/LogSeverity/symbolName``

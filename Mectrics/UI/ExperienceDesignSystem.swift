import SwiftUI
import MetricsKit

// MARK: - Experience tokens

/// Small shared token set for Mectrics surfaces. Values intentionally follow the
/// native macOS density instead of creating a separate custom-control language.
enum ExperienceSpacing {
    static let hairline: CGFloat = 1
    static let tiny: CGFloat = 2
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
}

enum ExperienceRadius {
    static let micro: CGFloat = 2
    static let compact: CGFloat = 6
    static let standard: CGFloat = 9
    static let panel: CGFloat = 12
}

enum ExperienceTypography {
    static let sectionTitle = Font.headline
    static let metricValue = Font.system(.title3, design: .rounded).weight(.semibold)
    static let supporting = Font.callout
    static let status = Font.caption.weight(.medium)
}

enum ExperienceChart {
    static let compactStrokeWidth: CGFloat = 1.5
    static let detailStrokeWidth: CGFloat = 2
    static let ringStrokeWidth: CGFloat = 3
    static let fillOpacity: Double = 0.16
    static let separatorOpacity: Double = 0.16
}

enum ExperienceSurface {
    static let floatingMaterial: Material = .ultraThin
    static let subtleFillOpacity: Double = 0.07
    static let selectedFillOpacity: Double = 0.16
    static let standardBorderOpacity: Double = 0.12
    static let increasedBorderOpacity: Double = 0.35
}

enum ExperienceMotion {
    static let quickDuration: TimeInterval = 0.12
    static let stateDuration: TimeInterval = 0.18

    static func stateChange(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: stateDuration)
    }
}

// MARK: - Shared native components

struct ExperienceSectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xSmall) {
            Text(title)
                .font(ExperienceTypography.sectionTitle)
            if let subtitle {
                Text(subtitle)
                    .font(ExperienceTypography.supporting)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct MetricValueText: View {
    let label: String
    let value: String
    let state: MetricDataState

    var body: some View {
        Text(value)
            .font(ExperienceTypography.metricValue)
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint(state.localizedName)
    }
}

struct MetricStatusBadge: View {
    let state: MetricDataState
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Label(state.localizedName, systemImage: state.symbolName)
            .font(ExperienceTypography.status)
            .foregroundStyle(state.tint)
            .padding(.horizontal, ExperienceSpacing.small)
            .padding(.vertical, ExperienceSpacing.xSmall)
            .background(
                Capsule()
                    .fill(state.tint.opacity(contrast == .increased ? 0.2 : 0.1))
            )
            .overlay {
                if contrast == .increased {
                    Capsule().strokeBorder(
                        state.tint,
                        lineWidth: ExperienceSpacing.hairline
                    )
                }
            }
            .accessibilityElement(children: .combine)
    }
}

struct MetricEmptyState: View {
    let state: MetricDataState
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: ExperienceSpacing.small) {
            Image(systemName: state.symbolName)
                .font(.title2)
                .foregroundStyle(state.tint)
                .accessibilityHidden(true)
            Text(state.localizedName)
                .font(.headline)
            Text(state.reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ExperienceSpacing.large)
        .accessibilityElement(children: .contain)
    }
}

struct InlineNotice: View {
    let state: MetricDataState
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ExperienceSpacing.small) {
            Image(systemName: state.symbolName)
                .foregroundStyle(state.tint)
                .accessibilityHidden(true)
            Text(state.reason)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: ExperienceSpacing.small)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

extension MetricDataState {
    var localizedName: String {
        switch self {
        case .collecting:
            return String(localized: "state.collecting", defaultValue: "Collecting")
        case .live:
            return String(localized: "state.live", defaultValue: "Live")
        case .unavailable:
            return String(localized: "state.unavailable", defaultValue: "Unavailable")
        case .disabled:
            return String(localized: "state.disabled", defaultValue: "Disabled")
        case .permissionRequired:
            return String(localized: "state.permissionRequired", defaultValue: "Permission required")
        case .stale:
            return String(localized: "state.stale", defaultValue: "Last known")
        case .error:
            return String(localized: "state.error", defaultValue: "Needs attention")
        }
    }

    var reason: String {
        switch self {
        case .collecting:
            return String(
                localized: "state.collecting.reason",
                defaultValue: "Waiting for the first reading."
            )
        case .live:
            return String(
                localized: "state.live.reason",
                defaultValue: "This reading is updating normally."
            )
        case .unavailable:
            return String(
                localized: "state.unavailable.reason",
                defaultValue: "This metric is not available on this Mac."
            )
        case .disabled:
            return String(
                localized: "state.disabled.reason",
                defaultValue: "This metric is not currently being monitored."
            )
        case .permissionRequired:
            return String(
                localized: "state.permissionRequired.reason",
                defaultValue: "Allow access to resume this reading."
            )
        case .stale:
            return String(
                localized: "state.stale.reason",
                defaultValue: "The last valid reading is older than expected."
            )
        case .error:
            return String(
                localized: "state.error.reason",
                defaultValue: "Mectrics could not refresh this reading."
            )
        }
    }

    var symbolName: String {
        switch self {
        case .collecting: return "ellipsis"
        case .live: return "checkmark.circle.fill"
        case .unavailable: return "slash.circle"
        case .disabled: return "minus.circle"
        case .permissionRequired: return "lock.trianglebadge.exclamationmark"
        case .stale: return "clock.badge.exclamationmark"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .live: return .green
        case .stale, .permissionRequired: return .orange
        case .error: return .red
        case .collecting, .unavailable, .disabled: return .secondary
        }
    }
}

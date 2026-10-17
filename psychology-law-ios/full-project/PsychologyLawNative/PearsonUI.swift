import SwiftUI

enum PearsonStyle {
    static let blue = Color(red: 0.000, green: 0.427, blue: 0.655)
    static let toolbar = Color(red: 0.541, green: 0.710, blue: 0.875)
    static let line = Color(red: 0.779, green: 0.836, blue: 0.885)
    static let answered = Color(red: 0.831, green: 0.929, blue: 1.000)
    static let text = Color(red: 0.095, green: 0.105, blue: 0.115)
}

struct PearsonFooterButton: View {
    let title: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.43)).frame(width: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1.0)
        .accessibilityLabel(title)
    }
}

struct PearsonSectionBand: View {
    let title: String
    var trailing: String = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 6)
            if !trailing.isEmpty {
                Text(trailing).font(.system(size: 10))
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(.white)
        .padding(.horizontal, 9)
        .frame(height: 23)
        .background(PearsonStyle.toolbar)
    }
}

struct PearsonRadio: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle().stroke(isSelected ? PearsonStyle.blue : Color.gray, lineWidth: 1.2)
                .frame(width: 16, height: 16)
            if isSelected {
                Circle().fill(PearsonStyle.blue).frame(width: 8, height: 8)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}
import SwiftUI

/// A short guide shown once after setup: what Trace does and where to look.
struct TourView: View {
    @EnvironmentObject private var model: AppModel
    @State private var index = 0

    private struct Slide {
        let symbol: String
        let title: String
        let text: String
    }

    private var slides: [Slide] {
        [
            Slide(symbol: "waveform.path.ecg", title: L("It records by itself"),
                  text: L("Trace notes the app, window, file and page in front of you. There is nothing to start or stop; it stays in the menu bar and keeps going when this window is closed.")),
            Slide(symbol: "chart.pie", title: L("See where the day went"),
                  text: L("Overview sums up today. In Timeline, open any tag down to a single file or page, or see the whole day side by side.")),
            Slide(symbol: "tag", title: L("Tags sort your time"),
                  text: L("Common apps and sites are tagged for you. Add your own tags under Tags, and rules under Rules to apply them automatically.")),
            Slide(symbol: "timer", title: L("Sessions and goals"),
                  text: L("Start a session and everything counts towards one tag until you stop. A daily goal keeps an eye on the tags that matter to you.")),
            Slide(symbol: "lock", title: L("Your records stay on this Mac"),
                  text: L("Nothing is uploaded. Pause from the menu bar at any time, and leave apps out under Settings.")),
        ]
    }

    var body: some View {
        let slide = slides[index]
        let isLast = index == slides.count - 1
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                Image(systemName: slide.symbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 84, height: 84)
                    .background(Theme.soft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text(slide.title).font(.system(size: 22, weight: .bold)).tracking(-0.2)
                    Text(slide.text)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 400, maxHeight: .infinity)
            .id(index)
            .transition(.opacity.combined(with: .offset(x: 16)))

            HStack(spacing: 6) {
                ForEach(slides.indices, id: \.self) { i in
                    Circle().fill(i == index ? Theme.accent : Theme.line).frame(width: 6, height: 6)
                }
            }
            .padding(.bottom, 22)
            .accessibilityHidden(true)

            HStack(spacing: 10) {
                if !isLast {
                    Button(L("Skip")) { model.finishTour() }.buttonStyle(.trLink)
                }
                Spacer()
                if index > 0 {
                    Button(L("Back")) { withAnimation(.easeOut(duration: 0.2)) { index -= 1 } }
                        .buttonStyle(TRButtonStyle(kind: .bordered, height: 32))
                }
                Button(isLast ? L("Get started") : L("Next")) {
                    if isLast { model.finishTour() } else { withAnimation(.easeOut(duration: 0.2)) { index += 1 } }
                }
                .buttonStyle(TRButtonStyle(kind: .prominent, height: 32))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(EdgeInsets(top: 36, leading: 36, bottom: 28, trailing: 36))
        .frame(width: 560, height: 420)
        .background(Theme.panel)
        .font(.system(size: 13))
        .foregroundStyle(Theme.ink)
    }
}

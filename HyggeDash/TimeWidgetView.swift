import SwiftUI

struct TimeWidgetView: View {
    @State private var currentTime = Date()

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(timeString)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(HyggeTheme.textPrimary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(dateString)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(HyggeTheme.textSecondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(HyggeTheme.cardBackground)
        .cornerRadius(24)
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: currentTime)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: currentTime)
    }
}

#Preview {
    TimeWidgetView()
        .padding()
        .frame(width: 400, height: 200)
        .background(HyggeTheme.background)
}
